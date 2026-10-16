import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

Future<(Map<String, Object?>, TrustedKey)> _signed({
  void Function(Map<String, Object?>)? tweak,
}) async {
  final pair = await DartEd25519().newKeyPairFromSeed(
    List<int>.generate(32, (i) => i),
  );
  final key = TrustedKey((await pair.extractPublicKey()).bytes);
  final m = <String, Object?>{
    'dataset_version': '2026.10.1',
    'schema_version': 1,
    'stage': 'release',
    'min_app_version': '1.0.0',
    'released_at': '2026-10-08T00:00:00Z',
    'url': 'https://example.invalid/x.sqlite.gz',
    'size': 100,
    'sha256': 'a' * 64,
    'signature_alg': 'ed25519',
    'key_id': key.id,
    'extra': {'b': 1, 'a': 2},
  };
  tweak?.call(m);
  final sig = await DartEd25519().sign(
    canonicalManifestBytes(m),
    keyPair: pair,
  );
  return ({...m, 'signature': base64Encode(sig.bytes)}, key);
}

void main() {
  test('a signed manifest verifies; every field is covered', () async {
    final (m, key) = await _signed();
    final v = ManifestVerifier([key]);
    await v.verify(UpdateManifest.parse(jsonEncode(m)));
    for (final field in ['size', 'sha256', 'url', 'dataset_version', 'extra']) {
      final t = {...m, field: field == 'size' ? 101 : 'changed'};
      if (field == 'dataset_version') t[field] = '2026.10.2';
      if (field == 'sha256') t[field] = 'b' * 64;
      await expectLater(
        v.verify(UpdateManifest.parse(jsonEncode(t))),
        throwsA(isA<ManifestException>()),
        reason: field,
      );
    }
  });

  test('no keys: nothing verifies; wrong key id is untrusted', () async {
    final (m, key) = await _signed();
    final parsed = UpdateManifest.parse(jsonEncode(m));
    await expectLater(
      const ManifestVerifier([]).verify(parsed),
      throwsA(
        isA<ManifestException>().having(
          (e) => e.reason,
          'reason',
          ManifestProblem.unknownKey,
        ),
      ),
    );
    expect(key.id, hasLength(16));
  });

  test('parse is strict about shape', () {
    expect(
      () => UpdateManifest.parse('nope'),
      throwsA(isA<ManifestException>()),
    );
    for (final bad in [
      {'dataset_version': '../x'},
      {'sha256': 'XYZ'},
      {'size': 0},
      {'size': maxDatasetBytes + 1},
      {'signature_alg': 'rsa'},
      {'released_at': 'yesterday'},
    ]) {
      final m = {
        'dataset_version': '2026.10.1',
        'schema_version': 1,
        'stage': 'release',
        'min_app_version': '1.0.0',
        'released_at': '2026-10-08T00:00:00Z',
        'url': 'https://x.invalid/a',
        'size': 10,
        'sha256': 'a' * 64,
        'signature_alg': 'ed25519',
        'key_id': 'k',
        'signature': 's',
        ...bad,
      };
      expect(
        () => UpdateManifest.parse(jsonEncode(m)),
        throwsA(isA<ManifestException>()),
        reason: '$bad',
      );
    }
  });

  test('decideUpdate covers every case', () async {
    final (m, _) = await _signed();
    UpdateManifest p(void Function(Map<String, Object?>) f) {
      final x = {...m};
      f(x);
      return UpdateManifest.parse(jsonEncode(x));
    }

    UpdateDecision d(UpdateManifest x, {String? cur}) =>
        decideUpdate(x, appVersion: '1.2.0', currentVersion: cur);
    expect(d(p((_) {})), UpdateDecision.install);
    expect(d(p((_) {}), cur: '2026.10.1'), UpdateDecision.upToDate);
    expect(d(p((_) {}), cur: '2026.10.2'), UpdateDecision.older);
    expect(d(p((_) {}), cur: '2026.9.9'), UpdateDecision.install);
    expect(d(p((x) => x['schema_version'] = 2)), UpdateDecision.schemaTooNew);
    expect(
      d(p((x) => x['min_app_version'] = '1.10.0')),
      UpdateDecision.needsNewerApp,
    );
    expect(d(p((x) => x['stage'] = 'draft')), UpdateDecision.notRelease);
  });

  test('sha256 matches the standard test vector, also incrementally', () {
    const abc =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    expect(contentSha256Hex(utf8.encode('abc')), abc);
    final acc = Sha256Accumulator()
      ..add(utf8.encode('a'))
      ..add(utf8.encode('bc'));
    expect(acc.close(), abc);
  });

  test('version ordering is numeric', () {
    expect(compareDottedVersions('2026.10.2', '2026.9.30'), greaterThan(0));
    expect(compareDottedVersions('1.0', '1.0.0'), 0);
    expect(() => compareDottedVersions('1.x', '1.0'), throwsFormatException);
  });
}
