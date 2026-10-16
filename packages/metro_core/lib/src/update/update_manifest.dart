import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:metro_core/src/dataset/schema.dart';

/// The remote manifest or its signature is not acceptable. Always safe to
/// show as "update skipped"; the active dataset is never touched.
class ManifestException implements Exception {
  const ManifestException(this.reason, this.message);

  final ManifestProblem reason;
  final String message;

  @override
  String toString() => 'ManifestException(${reason.name}): $message';
}

enum ManifestProblem {
  /// Not JSON / not an object / a required field is missing or malformed.
  malformed,

  /// `key_id` is not one of the public keys embedded in the app.
  unknownKey,

  /// The signature does not match (tampered, wrong key) or is not base64.
  badSignature,
}

/// Upper bound for a dataset the app will download (docs/sync.md: ~1.5 MB
/// today). A manifest asking for more is rejected before any download.
const maxDatasetBytes = 64 * 1024 * 1024;

final _versionRe = RegExp(r'^\d{1,6}(\.\d{1,6}){0,3}$');
final _sha256Re = RegExp(r'^[0-9a-f]{64}$');

/// Compares dotted numeric versions (`2026.10.1`, `1.0.0`). Missing parts
/// count as 0. Throws [FormatException] for anything else.
int compareDottedVersions(String a, String b) {
  List<int> parts(String v) {
    if (!_versionRe.hasMatch(v)) throw FormatException('bad version', v);
    return [for (final p in v.split('.')) int.parse(p)];
  }

  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

bool isValidDatasetVersion(String v) => _versionRe.hasMatch(v);

/// A parsed, **untrusted** remote manifest (docs/sync.md). Parsing only
/// checks shape; nothing in it may be used before [ManifestVerifier.verify]
/// has accepted the signature.
class UpdateManifest {
  const UpdateManifest._({
    required this.datasetVersion,
    required this.schemaVersion,
    required this.minAppVersion,
    required this.releasedAt,
    required this.url,
    required this.size,
    required this.sha256,
    required this.stage,
    required this.keyId,
    required this.signature,
    required this.raw,
    this.changelog = const {},
  });

  /// Strict parse of the manifest JSON text.
  factory UpdateManifest.parse(String text) {
    Never bad(String m) =>
        throw ManifestException(ManifestProblem.malformed, m);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      bad('not JSON');
    }
    if (decoded is! Map<String, Object?>) bad('not a JSON object');
    final obj = decoded;

    String str(String k, {RegExp? re, int max = 2048}) {
      final v = obj[k];
      if (v is! String || v.isEmpty || v.length > max) bad('"$k" missing');
      if (re != null && !re.hasMatch(v)) bad('"$k" malformed');
      return v;
    }

    int integer(String k, {required int min, required int max}) {
      final v = obj[k];
      if (v is! int || v < min || v > max) bad('"$k" missing or out of range');
      return v;
    }

    final released = DateTime.tryParse(str('released_at', max: 40));
    if (released == null) bad('"released_at" is not a timestamp');
    if (obj['signature_alg'] != 'ed25519') {
      bad('"signature_alg" must be ed25519');
    }
    final log = obj['changelog'];
    return UpdateManifest._(
      datasetVersion: str('dataset_version', re: _versionRe, max: 32),
      schemaVersion: integer('schema_version', min: 1, max: 1000),
      minAppVersion: str('min_app_version', re: _versionRe, max: 32),
      releasedAt: released.toUtc(),
      url: str('url'),
      size: integer('size', min: 1, max: maxDatasetBytes),
      sha256: str('sha256', re: _sha256Re, max: 64),
      stage: str('stage', max: 16),
      keyId: str('key_id', max: 64),
      signature: str('signature', max: 256),
      changelog: log is Map
          ? {
              for (final e in log.entries)
                if (e.key is String && e.value is String)
                  e.key as String: e.value as String,
            }
          : const {},
      raw: Map.unmodifiable(obj),
    );
  }

  final String datasetVersion;
  final int schemaVersion;
  final String minAppVersion;
  final DateTime releasedAt;

  /// Where to download the dataset (raw `.sqlite` or `.gz` of it).
  final String url;

  /// Size and sha256 of the **decompressed** dataset file.
  final int size;
  final String sha256;
  final String stage;
  final String keyId;
  final String signature;
  final Map<String, String> changelog;

  /// Every field as sent: the signature covers all of them, not just the ones
  /// this app version knows.
  final Map<String, Object?> raw;
}

/// A public Ed25519 key embedded in the app. Never a private key.
class TrustedKey {
  const TrustedKey(this.publicKey);

  /// From the base64 form printed by `data_pipeline keygen`.
  factory TrustedKey.fromBase64(String b64) {
    final bytes = base64Decode(b64);
    if (bytes.length != 32) {
      throw const FormatException('an Ed25519 public key is 32 bytes');
    }
    return TrustedKey(bytes);
  }

  final List<int> publicKey;

  /// Same derivation as the pipeline's `keyId`: first 16 hex chars of sha256.
  String get id => contentSha256Hex(publicKey).substring(0, 16);
}

/// Canonical signed bytes of a manifest: sorted keys, compact JSON, without
/// the `signature` field (identical to the pipeline's `signManifest`).
List<int> canonicalManifestBytes(Map<String, Object?> manifest) {
  final copy = {...manifest}..remove('signature');
  return utf8.encode(jsonEncode(_sorted(copy)));
}

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is Iterable) return [for (final x in v) _sorted(x)];
  return v;
}

/// Lower-case hex sha256 of [bytes].
String contentSha256Hex(List<int> bytes) =>
    _hex(const DartSha256().hashSync(bytes));

String _hex(Hash h) =>
    h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Incremental sha256 for files too large to hold twice in memory.
class Sha256Accumulator {
  Sha256Accumulator() : _sink = const DartSha256().newHashSink();

  final DartHashSink _sink;
  int length = 0;

  void add(List<int> chunk) {
    length += chunk.length;
    _sink.add(chunk);
  }

  /// Finishes the hash; the accumulator cannot be used afterwards.
  String close() {
    _sink.close();
    return _hex(_sink.hashSync());
  }
}

/// Verifies manifest signatures against the keys embedded in the app (current
/// + next, docs/sync.md "Key rotation"). With no keys nothing verifies, so an
/// app built without a key can never install an update.
class ManifestVerifier {
  const ManifestVerifier(this.keys);

  final List<TrustedKey> keys;

  Future<void> verify(UpdateManifest m) async {
    final key = keys.where((k) => k.id == m.keyId).firstOrNull;
    if (key == null) {
      throw ManifestException(
        ManifestProblem.unknownKey,
        'key ${m.keyId} is not trusted by this app',
      );
    }
    final List<int> sig;
    try {
      sig = base64Decode(m.signature);
    } on FormatException {
      throw const ManifestException(
        ManifestProblem.badSignature,
        'signature is not base64',
      );
    }
    final ok = await DartEd25519().verify(
      canonicalManifestBytes(m.raw),
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(key.publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) {
      throw const ManifestException(
        ManifestProblem.badSignature,
        'signature does not match (tampered or wrong key)',
      );
    }
  }
}

/// What to do with a verified manifest.
enum UpdateDecision {
  /// Newer, compatible and allowed: download it.
  install,

  /// Same version as the one in use.
  upToDate,

  /// Older than the one in use: never downgrade.
  older,

  /// Needs a newer schema than this app understands.
  schemaTooNew,

  /// Schema older than this app still reads.
  schemaTooOld,

  /// `min_app_version` is above this app: Settings shows "Update app".
  needsNewerApp,

  /// A draft dataset, not allowed in this build.
  notRelease,
}

/// Decides from the (verified) manifest alone, before any download.
/// [currentVersion] is the best dataset in use (null: none).
UpdateDecision decideUpdate(
  UpdateManifest m, {
  required String appVersion,
  String? currentVersion,
  bool allowDraft = false,
}) {
  if (m.schemaVersion > supportedSchemaMax) return UpdateDecision.schemaTooNew;
  if (m.schemaVersion < minSupportedSchemaVersion) {
    return UpdateDecision.schemaTooOld;
  }
  if (compareDottedVersions(m.minAppVersion, appVersion) > 0) {
    return UpdateDecision.needsNewerApp;
  }
  if (m.stage != 'release' && !allowDraft) return UpdateDecision.notRelease;
  if (currentVersion != null) {
    final c = compareDottedVersions(m.datasetVersion, currentVersion);
    if (c == 0) return UpdateDecision.upToDate;
    if (c < 0) return UpdateDecision.older;
  }
  return UpdateDecision.install;
}

/// Highest dataset schema this build reads.
const supportedSchemaMax = currentSchemaVersion;
