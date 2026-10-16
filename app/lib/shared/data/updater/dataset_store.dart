import 'dart:convert';
import 'dart:io';

import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';

/// Which downloaded datasets are in use (`current.json`, docs/offline.md).
class DatasetPointer {
  const DatasetPointer({this.active, this.previous, this.bad = const []});

  final String? active;
  final String? previous;

  /// Versions that downloaded fine but failed to load on the device. They are
  /// never installed again.
  final List<String> bad;

  Map<String, Object?> toJson() => {
    'active': active,
    'previous': previous,
    'bad': bad,
  };
}

/// The installed-datasets directory:
/// `<root>/<version>/metro.sqlite`, `<root>/current.json`, `<root>/.staging/`.
///
/// Every change goes through a staging directory and a rename; the pointer is
/// written to a temp file and renamed. A reader therefore sees either the old
/// or the new state, never half of an update.
class DatasetStore {
  DatasetStore(this.root);

  final Directory root;

  static const datasetFileName = 'metro.sqlite';
  static const _maxBad = 8;

  File get _pointerFile => File('${root.path}/current.json');
  File get _checkFile => File('${root.path}/last_check.txt');
  Directory get stagingDir => Directory('${root.path}/.staging');

  String pathOf(String version) => '${root.path}/$version/$datasetFileName';

  /// The pointer, or an empty one if it is missing or unreadable. Contents are
  /// never trusted: versions must look like versions (no path tricks).
  DatasetPointer read() {
    try {
      final j = jsonDecode(_pointerFile.readAsStringSync());
      if (j is! Map) return const DatasetPointer();
      String? v(Object? x) =>
          x is String && isValidDatasetVersion(x) ? x : null;
      return DatasetPointer(
        active: v(j['active']),
        previous: v(j['previous']),
        bad: [
          if (j['bad'] is List)
            for (final b in j['bad'] as List)
              if (v(b) != null) b as String,
        ],
      );
    } on Object {
      return const DatasetPointer();
    }
  }

  /// The installed datasets to try after a developer override: active, then
  /// the previous one. Missing files are skipped by the bootstrap itself.
  List<DatasetCandidate> candidates() {
    final p = read();
    return [
      if (p.active != null)
        DatasetCandidate(label: 'updated ${p.active}', path: pathOf(p.active!)),
      if (p.previous != null)
        DatasetCandidate(
          label: 'previous ${p.previous}',
          path: pathOf(p.previous!),
        ),
    ];
  }

  /// The best installed version (what an update must beat), or null.
  String? get activeVersion {
    final p = read();
    final v = p.active;
    return v != null && File(pathOf(v)).existsSync() ? v : null;
  }

  /// A fresh empty directory for one update attempt.
  Directory newAttemptDir() {
    stagingDir.createSync(recursive: true);
    return stagingDir.createTempSync('attempt-');
  }

  /// Makes [stagedFile] (already fully verified) the active dataset.
  ///
  /// Moves it into `<root>/<version>/` then rewrites the pointer. If anything
  /// fails the new directory is removed and the pointer is as before: the
  /// previous dataset stays active (rollback).
  void install(File stagedFile, String version) {
    if (!isValidDatasetVersion(version)) {
      throw ArgumentError.value(version, 'version');
    }
    final before = read();
    final dest = Directory('${root.path}/$version');
    final backup = Directory('${root.path}/.replaced-$version');
    var movedAside = false;
    try {
      root.createSync(recursive: true);
      if (dest.existsSync()) {
        if (before.active == version || before.previous == version) {
          // never replace a dataset that is in use
          throw StateError('version $version is already installed');
        }
        if (backup.existsSync()) backup.deleteSync(recursive: true);
        dest.renameSync(backup.path);
        movedAside = true;
      }
      dest.createSync();
      stagedFile.renameSync('${dest.path}/$datasetFileName');
      _writePointer(
        DatasetPointer(
          active: version,
          previous: before.active,
          bad: before.bad,
        ),
      );
    } on Object {
      try {
        if (dest.existsSync()) dest.deleteSync(recursive: true);
        if (movedAside) backup.renameSync(dest.path);
      } on Object {
        // best effort: the pointer was not changed either way
      }
      rethrow;
    }
    if (movedAside && backup.existsSync()) backup.deleteSync(recursive: true);
    prune();
  }

  /// A dataset that failed to load on the device: drop it from use and fall
  /// back to the previous one (docs/offline.md failure matrix).
  void markBad(String version) {
    final p = read();
    if (!isValidDatasetVersion(version)) return;
    final bad = [...p.bad.where((b) => b != version), version];
    final trimmed = bad.length > _maxBad
        ? bad.sublist(bad.length - _maxBad)
        : bad;
    _writePointer(
      DatasetPointer(
        active: p.active == version ? p.previous : p.active,
        previous: p.previous == version || p.active == version
            ? null
            : p.previous,
        bad: trimmed,
      ),
    );
    prune();
  }

  /// Deletes every dataset directory except active and previous, and leftover
  /// staging from finished attempts.
  void prune() {
    final p = read();
    final keep = {p.active, p.previous};
    if (!root.existsSync()) return;
    for (final e in root.listSync()) {
      if (e is! Directory) continue;
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name == '.staging') continue;
      if (name.startsWith('.replaced-') ||
          (isValidDatasetVersion(name) && !keep.contains(name))) {
        try {
          e.deleteSync(recursive: true);
        } on FileSystemException {
          // in use or locked: next prune
        }
      }
    }
  }

  void _writePointer(DatasetPointer p) {
    root.createSync(recursive: true);
    final tmp = File('${_pointerFile.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(p.toJson()), flush: true);
    tmp.renameSync(_pointerFile.path);
  }

  DateTime? get lastCheck {
    try {
      return DateTime.tryParse(_checkFile.readAsStringSync())?.toUtc();
    } on Object {
      return null;
    }
  }

  void recordCheck(DateTime at) {
    root.createSync(recursive: true);
    _checkFile.writeAsStringSync(at.toUtc().toIso8601String(), flush: true);
  }
}
