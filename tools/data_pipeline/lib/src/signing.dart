import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:data_pipeline/src/util.dart';
import 'package:sqlite3/sqlite3.dart';

class SigningException implements Exception {
  SigningException(this.message);
  final String message;
  @override
  String toString() => 'SigningException: $message';
}

/// Environment variable holding the base64 Ed25519 private seed (CI secret).
const signingKeyEnv = 'METROMITRA_SIGNING_KEY';

final _ed25519 = DartEd25519();

class GeneratedKey {
  const GeneratedKey(this.privateSeed, this.publicKey);

  /// 32-byte seed. Secret: only ever lives in the CI secret store.
  final List<int> privateSeed;
  final List<int> publicKey;
}

/// A fresh Ed25519 key pair.
Future<GeneratedKey> generateKey() async {
  final pair = await _ed25519.newKeyPair();
  final data = await pair.extract();
  return GeneratedKey(
    await pair.extractPrivateKeyBytes(),
    data.publicKey.bytes,
  );
}

String keyId(List<int> publicKey) => sha256Hex(publicKey).substring(0, 16);

/// Manifest for [sqlitePath] (docs/sync.md). Contains no signature yet.
/// Refuses drafts and test data: they must never be signed for release.
Map<String, Object?> buildManifest(
  String sqlitePath, {
  String minAppVersion = '1.0.0',
  String? url,
  Map<String, String>? changelog,
  bool allowDraft = false,
}) {
  final file = File(sqlitePath);
  if (!file.existsSync()) throw SigningException('No dataset at $sqlitePath');
  final bytes = file.readAsBytesSync();
  {
    final source = sqlite3.open(sqlitePath, mode: OpenMode.readOnly);
    try {
      final meta = {
        for (final r in source.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      };
      final sources = [
        for (final r in source.select(
          'SELECT id, license, version, sha256 FROM source ORDER BY id',
        ))
          {
            'id': r['id'],
            'license': r['license'],
            'version': r['version'],
            'sha256': r['sha256'],
          },
      ];
      if (!allowDraft &&
          (meta['stage'] == 'draft' || meta['is_test_data'] == 'true')) {
        throw SigningException(
          'Refusing to sign a ${meta['stage'] == 'draft' ? 'draft' : 'test'} '
          'dataset. Drafts and test data must never be released '
          '(--allow-draft overrides for local experiments only).',
        );
      }
      return {
        'dataset_version': meta['dataset_version'],
        'schema_version': int.tryParse(meta['schema_version'] ?? ''),
        'stage': meta['stage'] ?? 'release',
        'min_app_version': minAppVersion,
        'released_at': meta['built_at'],
        'url': ?url,
        'size': bytes.length,
        'sha256': sha256Hex(bytes),
        'attribution': meta['attribution'],
        'sources': sources,
        'changelog': ?changelog,
        'signature_alg': 'ed25519',
      };
    } on SqliteException catch (e) {
      throw SigningException('Not a MetroMitra dataset: ${e.message}');
    } finally {
      source.close();
    }
  }
}

List<int> _signedBytes(Map<String, Object?> manifest) {
  final copy = {...manifest}..remove('signature');
  return utf8.encode(canonicalJson(copy, pretty: false));
}

/// Adds `key_id` and `signature` (base64 Ed25519 over the canonical manifest
/// without the signature, per docs/sync.md).
Future<Map<String, Object?>> signManifest(
  Map<String, Object?> manifest,
  List<int> privateSeed,
) async {
  if (privateSeed.length != 32) {
    throw SigningException('Signing key must be a 32-byte seed (base64).');
  }
  final pair = await _ed25519.newKeyPairFromSeed(privateSeed);
  final pub = (await pair.extractPublicKey()).bytes;
  final withKey = {...manifest, 'key_id': keyId(pub)};
  final sig = await _ed25519.sign(_signedBytes(withKey), keyPair: pair);
  return {...withKey, 'signature': base64Encode(sig.bytes)};
}

class VerifyResult {
  const VerifyResult(this.problems);
  final List<String> problems;
  bool get ok => problems.isEmpty;
}

/// Checks the signature and, if [sqlitePath] is given, size and sha256.
Future<VerifyResult> verifyManifest(
  Map<String, Object?> manifest,
  List<int> publicKey, {
  String? sqlitePath,
}) async {
  final problems = <String>[];
  final sig = manifest['signature'];
  if (sig is! String) {
    problems.add('manifest has no signature');
  } else {
    try {
      final ok = await _ed25519.verify(
        _signedBytes(manifest),
        signature: Signature(
          base64Decode(sig),
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
      if (!ok) problems.add('signature does not match (tampered or wrong key)');
    } on FormatException {
      problems.add('signature is not valid base64');
    }
  }
  if (manifest['key_id'] != keyId(publicKey)) {
    problems.add('manifest key_id does not match the supplied public key');
  }
  if (sqlitePath != null) {
    final f = File(sqlitePath);
    if (!f.existsSync()) {
      problems.add('dataset file missing');
    } else {
      final bytes = f.readAsBytesSync();
      if (bytes.length != manifest['size']) {
        problems.add('size ${bytes.length} != manifest ${manifest['size']}');
      }
      if (sha256Hex(bytes) != manifest['sha256']) {
        problems.add('sha256 does not match the dataset file');
      }
    }
  }
  return VerifyResult(problems);
}
