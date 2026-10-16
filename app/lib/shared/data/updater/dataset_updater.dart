import 'dart:async';
import 'dart:io';

import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';
import 'package:metromitra/shared/data/updater/dataset_store.dart';
import 'package:metromitra/shared/data/updater/update_transport.dart';

/// How one update attempt ended. Everything except [installed] leaves the
/// datasets exactly as they were.
enum UpdateStatus {
  installed,
  upToDate,
  older,
  schemaTooNew,
  schemaTooOld,
  needsNewerApp,
  notRelease,
  knownBad,

  /// No connection, timeout, HTTP error, or the download was cut short
  /// (a resumable partial file may remain).
  network,
  manifestInvalid,

  /// Unknown key or signature mismatch.
  untrusted,

  /// Size or sha256 differs from the signed manifest, or the file is not
  /// the gzip/sqlite it claims to be.
  checksum,

  /// Readable, but not a valid dataset (or disagrees with its manifest).
  datasetInvalid,
  installFailed,

  /// No manifest address or no trusted key in this build.
  disabled,
}

class UpdateResult {
  const UpdateResult(this.status, {this.version, this.detail = ''});

  final UpdateStatus status;

  /// The manifest's dataset version, once it is known and trusted.
  final String? version;
  final String detail;

  bool get installed => status == UpdateStatus.installed;
}

/// Manifest -> download -> checksum -> signature-checked metadata -> dataset
/// validation -> atomic install (docs/sync.md). Nothing remote is trusted
/// before the signature check, and nothing is activated before every check
/// passed; any failure keeps the current dataset.
class DatasetUpdater {
  DatasetUpdater({
    required this.store,
    required this.transport,
    required this.verifier,
    required this.appVersion,
    this.manifestUrl,
    this.policy = DatasetPolicy.strict,
    this.loader = loadDatasetInIsolate,
    this.bundledVersion,
  });

  final DatasetStore store;
  final UpdateTransport transport;
  final ManifestVerifier verifier;
  final String appVersion;
  final Uri? manifestUrl;
  final DatasetPolicy policy;

  /// Reads + validates a file (isolate in the app, sync in tests).
  final DatasetLoader loader;

  /// Version of the dataset bundled in the app, if any (an update must be
  /// newer than it too).
  final String? bundledVersion;

  bool _running = false;

  bool get enabled => manifestUrl != null && verifier.keys.isNotEmpty;

  /// Runs one full attempt. Never throws; never touches the active dataset
  /// unless every check passed.
  Future<UpdateResult> run() async {
    if (!enabled) return const UpdateResult(UpdateStatus.disabled);
    if (_running) return const UpdateResult(UpdateStatus.disabled);
    _running = true;
    try {
      return await _run();
    } on Object catch (e) {
      return UpdateResult(
        UpdateStatus.installFailed,
        detail: '${e.runtimeType}',
      );
    } finally {
      _running = false;
    }
  }

  Future<UpdateResult> _run() async {
    // 1. manifest: untrusted until the signature is checked
    final String text;
    try {
      text = await transport.fetchManifest(manifestUrl!);
    } on TransportException catch (e) {
      return UpdateResult(UpdateStatus.network, detail: e.message);
    }
    final UpdateManifest manifest;
    try {
      manifest = UpdateManifest.parse(text);
      await verifier.verify(manifest);
    } on ManifestException catch (e) {
      return UpdateResult(
        e.reason == ManifestProblem.malformed
            ? UpdateStatus.manifestInvalid
            : UpdateStatus.untrusted,
        detail: e.message,
      );
    }

    // 2. is it worth downloading? (version, schema, app version, stage)
    final current = _newest(store.activeVersion, bundledVersion);
    final decision = decideUpdate(
      manifest,
      appVersion: appVersion,
      currentVersion: current,
      allowDraft: policy.allowDraft,
    );
    if (decision != UpdateDecision.install) {
      return UpdateResult(_status(decision), version: manifest.datasetVersion);
    }
    if (store.read().bad.contains(manifest.datasetVersion)) {
      return UpdateResult(
        UpdateStatus.knownBad,
        version: manifest.datasetVersion,
        detail: 'this version failed on the device before',
      );
    }
    final url = Uri.tryParse(manifest.url);
    if (url == null || !url.hasScheme) {
      return UpdateResult(
        UpdateStatus.manifestInvalid,
        version: manifest.datasetVersion,
        detail: 'bad dataset address',
      );
    }

    // 3. download into a temp area (resumable), never near the active file
    final attempt = store.newAttemptDir();
    final part = File(
      '${store.stagingDir.path}/dl-${manifest.sha256.substring(0, 16)}.part',
    );
    try {
      try {
        await transport.download(url, part, maxBytes: maxDatasetBytes);
      } on TransportException catch (e) {
        // keep the partial file: the next attempt resumes it
        return UpdateResult(
          UpdateStatus.network,
          version: manifest.datasetVersion,
          detail: e.message,
        );
      }

      // 4. unpack + checksum against the signed manifest
      final staged = File('${attempt.path}/${DatasetStore.datasetFileName}');
      final problem = await _unpackAndCheck(part, staged, manifest, url);
      if (problem != null) {
        _delete(part); // not the file the manifest describes: start over
        return UpdateResult(
          UpdateStatus.checksum,
          version: manifest.datasetVersion,
          detail: problem,
        );
      }
      _delete(part);

      // 5. validate with the app's own loader and rules
      final checked = await bootstrapDataset(
        candidates: [DatasetCandidate(label: 'update', path: staged.path)],
        policy: policy,
        loader: loader,
      );
      if (checked is! BootstrapReady) {
        final a = (checked as BootstrapFailed).attempts.first;
        return UpdateResult(
          UpdateStatus.datasetInvalid,
          version: manifest.datasetVersion,
          detail: '${a.problem.name}: ${a.detail}',
        );
      }
      final snap = checked.snapshot;
      if (snap.datasetVersion != manifest.datasetVersion ||
          snap.schemaVersion != manifest.schemaVersion ||
          (manifest.stage == 'release' && snap.isDraft)) {
        return UpdateResult(
          UpdateStatus.datasetInvalid,
          version: manifest.datasetVersion,
          detail: 'the dataset does not match its manifest',
        );
      }

      // 6. atomic install; failure rolls back inside the store
      try {
        store.install(staged, manifest.datasetVersion);
      } on Object catch (e) {
        return UpdateResult(
          UpdateStatus.installFailed,
          version: manifest.datasetVersion,
          detail: '${e.runtimeType}',
        );
      }
      return UpdateResult(
        UpdateStatus.installed,
        version: manifest.datasetVersion,
      );
    } finally {
      try {
        attempt.deleteSync(recursive: true);
      } on Object {
        // swept by the next prune
      }
    }
  }

  /// Null when [out] now holds exactly the dataset the manifest signed;
  /// otherwise a short reason.
  Future<String?> _unpackAndCheck(
    File part,
    File out,
    UpdateManifest m,
    Uri url,
  ) async {
    if (!part.existsSync()) return 'nothing downloaded';
    final gz = url.path.endsWith('.gz');
    final hash = Sha256Accumulator();
    final sink = out.openWrite();
    var failed = false;
    try {
      final body = gz
          ? part.openRead().transform(gzip.decoder)
          : part.openRead();
      await for (final c in body) {
        if (hash.length + c.length > m.size) {
          failed = true; // bigger than signed (also stops decompression bombs)
          break;
        }
        hash.add(c);
        sink.add(c);
      }
    } on FormatException {
      failed = true;
    } on FileSystemException {
      failed = true;
    } on Object {
      failed = true; // damaged gzip stream
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (failed) return gz ? 'damaged or oversized download' : 'oversized file';
    if (hash.length != m.size) return 'size ${hash.length} != ${m.size}';
    if (hash.close() != m.sha256) return 'sha256 mismatch';
    return null;
  }

  static String? _newest(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    return compareDottedVersions(a, b) >= 0 ? a : b;
  }

  static UpdateStatus _status(UpdateDecision d) => switch (d) {
    UpdateDecision.install => UpdateStatus.installed,
    UpdateDecision.upToDate => UpdateStatus.upToDate,
    UpdateDecision.older => UpdateStatus.older,
    UpdateDecision.schemaTooNew => UpdateStatus.schemaTooNew,
    UpdateDecision.schemaTooOld => UpdateStatus.schemaTooOld,
    UpdateDecision.needsNewerApp => UpdateStatus.needsNewerApp,
    UpdateDecision.notRelease => UpdateStatus.notRelease,
  };

  static void _delete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } on Object {
      // nothing to do
    }
  }
}

/// At most one check per 24 h (docs/sync.md). A failed attempt also counts,
/// so a broken server is not hammered; the next day tries again.
bool updateIsDue(DateTime? lastCheck, DateTime now) =>
    lastCheck == null ||
    now.difference(lastCheck) >= const Duration(hours: 24) ||
    now.isBefore(lastCheck);
