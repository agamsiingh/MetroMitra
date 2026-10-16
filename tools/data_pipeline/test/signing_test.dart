import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/data_pipeline.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:test/test.dart';

import 'support/support.dart';

void main() {
  late Directory tmp;
  late String release; // a non-draft, non-test dataset
  late String draft;
  late GeneratedKey key;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('signing_test_');
    final ws = Workspace.create(
      overlay: '''
operators:
  - osm_operator: "TEST Operator"
    id: test-op
    name_hi: "ऑपरेटर"
    reason: r
    source: mitra-curated
    verified_on: "2026-10-01"
stations:
  - id: test-north
    name_hi: "टेस्ट नॉर्थ"
    reason: r
    source: mitra-curated
    verified_on: "2026-10-01"
''',
    );
    buildDataset(ws.paths);
    release = '${tmp.path}/release.sqlite';
    File('${ws.root}/build/pipeline/metro.sqlite').copySync(release);
    ws.dispose();

    final ws2 = Workspace.create();
    buildDataset(ws2.paths);
    draft = '${tmp.path}/draft.sqlite';
    File('${ws2.root}/build/pipeline/metro.sqlite').copySync(draft);
    ws2.dispose();
    key = await generateKey();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('manifest', () {
    test(
      'describes the dataset: version, schema, size, sha256, sources, attribution',
      () {
        final m = buildManifest(
          release,
          url: 'https://example.invalid/m.sqlite',
          changelog: {'en': 'first'},
        );
        final bytes = File(release).readAsBytesSync();
        expect(m['dataset_version'], '2026.10.0');
        expect(m['schema_version'], currentSchemaVersion);
        expect(m['stage'], 'release');
        expect(m['size'], bytes.length);
        expect(m['sha256'], sha256Hex(bytes));
        expect(m['released_at'], '2026-10-05T11:00:00Z');
        expect(m['min_app_version'], '1.0.0');
        expect(m['url'], 'https://example.invalid/m.sqlite');
        expect(m['attribution'], contains('OpenStreetMap'));
        final sources = (m['sources']! as List).cast<Map<String, Object?>>();
        expect(
          sources.map((s) => s['id']),
          containsAll(['osm-overpass', 'wikidata']),
        );
        expect(
          sources.firstWhere((s) => s['id'] == 'osm-overpass')['license'],
          'ODbL-1.0',
        );
        expect(m.containsKey('signature'), isFalse);
      },
    );

    test('is deterministic', () {
      expect(
        canonicalJson(buildManifest(release)),
        canonicalJson(buildManifest(release)),
      );
    });

    test('refuses drafts', () {
      expect(
        () => buildManifest(draft),
        throwsA(
          isA<SigningException>().having(
            (e) => e.message,
            'm',
            contains('draft'),
          ),
        ),
      );
    });

    test('refuses test data', () {
      final fixture = YamlDatasetLoader.loadFile(
        '../../data/fixtures/mini_network/dataset.yaml',
      );
      DatasetWriter.writeFile(fixture, '${tmp.path}/fixture.sqlite');
      expect(
        () => buildManifest('${tmp.path}/fixture.sqlite'),
        throwsA(
          isA<SigningException>().having(
            (e) => e.message,
            'm',
            contains('test'),
          ),
        ),
      );
    });

    test('--allow-draft is an explicit local override', () {
      expect(buildManifest(draft, allowDraft: true)['stage'], 'draft');
    });

    test('missing file or non-dataset file', () {
      expect(
        () => buildManifest('${tmp.path}/none.sqlite'),
        throwsA(isA<SigningException>()),
      );
      File('${tmp.path}/junk.sqlite').writeAsStringSync('junk' * 100);
      expect(
        () => buildManifest('${tmp.path}/junk.sqlite'),
        throwsA(isA<SigningException>()),
      );
    });
  });

  group('Ed25519 signing', () {
    test(
      'the app verifier (metro_core) accepts what the pipeline signs',
      () async {
        final signed = await signManifest({
          ...buildManifest(release),
          'url': 'https://example.invalid/m.sqlite',
        }, key.privateSeed);
        final verifier = ManifestVerifier([TrustedKey(key.publicKey)]);
        final m = UpdateManifest.parse(jsonEncode(signed));
        await verifier.verify(m); // must not throw
        expect(m.sha256, signed['sha256']);
        final tampered = UpdateManifest.parse(
          jsonEncode({...signed, 'size': (signed['size']! as int) + 1}),
        );
        await expectLater(
          verifier.verify(tampered),
          throwsA(isA<ManifestException>()),
        );
      },
    );

    test('sign then verify succeeds, including the file hash', () async {
      final signed = await signManifest(
        buildManifest(release),
        key.privateSeed,
      );
      expect(signed['signature'], isA<String>());
      expect(signed['key_id'], keyId(key.publicKey));
      final r = await verifyManifest(
        signed,
        key.publicKey,
        sqlitePath: release,
      );
      expect(r.ok, isTrue, reason: '${r.problems}');
    });

    test(
      'signatures are deterministic for the same key and manifest',
      () async {
        final a = await signManifest(buildManifest(release), key.privateSeed);
        final b = await signManifest(buildManifest(release), key.privateSeed);
        expect(a['signature'], b['signature']);
      },
    );

    test('tampered manifest field is detected', () async {
      final signed = await signManifest(
        buildManifest(release),
        key.privateSeed,
      );
      for (final (field, value) in [
        ('dataset_version', '2099.01.0'),
        ('sha256', 'f' * 64),
        ('size', 1),
        ('min_app_version', '0.0.1'),
      ]) {
        final r = await verifyManifest({
          ...signed,
          field: value,
        }, key.publicKey);
        expect(r.ok, isFalse, reason: field);
        expect(r.problems.join(), contains('signature'));
      }
    });

    test('wrong public key', () async {
      final signed = await signManifest(
        buildManifest(release),
        key.privateSeed,
      );
      final other = await generateKey();
      final r = await verifyManifest(signed, other.publicKey);
      expect(r.ok, isFalse);
      expect(r.problems.join(), contains('key_id'));
    });

    test('modified dataset file: sha256 and size mismatch', () async {
      final signed = await signManifest(
        buildManifest(release),
        key.privateSeed,
      );
      final f = File(release);
      f.writeAsBytesSync(f.readAsBytesSync()..[100] ^= 1);
      final r = await verifyManifest(
        signed,
        key.publicKey,
        sqlitePath: release,
      );
      expect(r.ok, isFalse);
      expect(r.problems.join(), contains('sha256'));
      f.writeAsBytesSync(f.readAsBytesSync().sublist(0, 500));
      final r2 = await verifyManifest(
        signed,
        key.publicKey,
        sqlitePath: release,
      );
      expect(r2.problems.join(), contains('size'));
    });

    test('missing or malformed signature', () async {
      final m = buildManifest(release);
      expect(
        (await verifyManifest(m, key.publicKey)).problems.join(),
        contains('no signature'),
      );
      final bad = {
        ...m,
        'signature': '***not base64***',
        'key_id': keyId(key.publicKey),
      };
      expect((await verifyManifest(bad, key.publicKey)).ok, isFalse);
    });

    test('missing dataset file is reported', () async {
      final signed = await signManifest(
        buildManifest(release),
        key.privateSeed,
      );
      final r = await verifyManifest(
        signed,
        key.publicKey,
        sqlitePath: '${tmp.path}/gone.sqlite',
      );
      expect(r.problems.join(), contains('missing'));
    });

    test('a seed of the wrong length is rejected', () {
      expect(
        signManifest(buildManifest(release), [1, 2, 3]),
        throwsA(isA<SigningException>()),
      );
    });

    test('keys are 32 bytes and distinct', () async {
      final other = await generateKey();
      expect(key.privateSeed, hasLength(32));
      expect(key.publicKey, hasLength(32));
      expect(other.publicKey, isNot(key.publicKey));
    });
  });

  group('CLI: keygen, sign, verify', () {
    Future<(int, List<String>, List<String>)> cli(
      List<String> args, {
      Map<String, String> env = const {},
    }) async {
      final out = <String>[];
      final err = <String>[];
      final code = await run(
        args,
        out: out.add,
        err: err.add,
        environment: env,
      );
      return (code, out, err);
    }

    test('full flow with the signing key only in the environment', () async {
      final keyFile = '${tmp.path}/private.key';
      final gen = await cli(['keygen', '--private-out', keyFile]);
      expect(gen.$1, 0);
      final publicKey = gen.$2
          .firstWhere((l) => l.startsWith('Public key'))
          .split(': ')
          .last;
      final seed = File(keyFile).readAsStringSync();

      final signed = await cli(
        ['sign', '--input', release, '--out', '${tmp.path}/manifest.json'],
        env: {signingKeyEnv: seed},
      );
      expect(signed.$1, 0, reason: signed.$3.join());
      expect(
        signed.$2.join(),
        isNot(contains(seed)),
        reason: 'the private key is never printed',
      );

      final ok = await cli([
        'verify',
        '--manifest',
        '${tmp.path}/manifest.json',
        '--public-key',
        publicKey,
        '--input',
        release,
      ]);
      expect(ok.$1, 0, reason: ok.$3.join());

      final m =
          jsonDecode(File('${tmp.path}/manifest.json').readAsStringSync())
              as Map<String, Object?>;
      File('${tmp.path}/manifest.json').writeAsStringSync(
        canonicalJson({...m, 'dataset_version': '2099.01.0'}),
      );
      final bad = await cli([
        'verify',
        '--manifest',
        '${tmp.path}/manifest.json',
        '--public-key',
        publicKey,
      ]);
      expect(bad.$1, 1);
      expect(bad.$3.join(), contains('VERIFY FAILED'));
    });

    test(
      'sign without a key, with a bad key, or on a draft is refused (exit 2)',
      () async {
        expect((await cli(['sign', '--input', release])).$1, 2);
        expect(
          (await cli(
            ['sign', '--input', release],
            env: {signingKeyEnv: '***'},
          )).$1,
          2,
        );
        final seed = base64Encode(key.privateSeed);
        final d = await cli(
          ['sign', '--input', draft],
          env: {signingKeyEnv: seed},
        );
        expect(d.$1, 2);
        expect(d.$3.join(), contains('draft'));
        expect(
          File('${File(draft).parent.path}/manifest.json').existsSync(),
          isFalse,
        );
      },
    );

    test('keygen refuses to overwrite and needs an output path', () async {
      final f = '${tmp.path}/k.key';
      expect((await cli(['keygen', '--private-out', f])).$1, 0);
      expect((await cli(['keygen', '--private-out', f])).$1, 2);
      expect((await cli(['keygen'])).$1, 64);
    });

    test('verify reads the public key from a file', () async {
      final seed = base64Encode(key.privateSeed);
      await cli(
        ['sign', '--input', release, '--out', '${tmp.path}/m.json'],
        env: {signingKeyEnv: seed},
      );
      File(
        '${tmp.path}/pub.txt',
      ).writeAsStringSync(base64Encode(key.publicKey));
      expect(
        (await cli([
          'verify',
          '--manifest',
          '${tmp.path}/m.json',
          '--public-key',
          '${tmp.path}/pub.txt',
        ])).$1,
        0,
      );
    });
  });
}
