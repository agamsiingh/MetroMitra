import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/data_pipeline.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:test/test.dart';

import 'support/support.dart';

/// Runs from tools/data_pipeline; the fixture lives at the repo root.
const _fixture = '../../data/fixtures/mini_network/dataset.yaml';

typedef Result = ({int code, List<String> out, List<String> err});

Future<Result> cli(
  List<String> args, {
  BuildPaths? paths,
  HttpTransport? transport,
  Map<String, String> env = const {},
}) async {
  final out = <String>[];
  final err = <String>[];
  final code = await run(
    args,
    out: out.add,
    err: err.add,
    transport: transport,
    sleep: (_) async {},
    now: () => DateTime.utc(2026, 10, 5, 12),
    environment: env,
    paths: paths ?? const BuildPaths(),
  );
  return (code: code, out: out, err: err);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pipeline_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('usage', () {
    test('no command prints usage and exits 64', () async {
      final r = await cli([]);
      expect(r.code, 64);
      expect(r.out.join(), contains('fetch'));
    });

    test('--offline alone is not a command', () async {
      expect((await cli(['--offline'])).code, 64);
    });

    test('unknown commands and options are rejected', () async {
      expect((await cli(['frobnicate'])).code, 64);
      expect((await cli(['build', '--nope'])).code, 64);
      expect((await cli(['build', '--out'])).code, 64);
    });

    test('--help lists every command', () async {
      final r = await cli(['--help']);
      expect(r.code, 0);
      for (final c in pipelineCommands) {
        expect(r.out.join(), contains(c));
      }
    });
  });

  group('validate / build from authoring YAML (M1 path)', () {
    test('fixture is valid (warnings allowed)', () async {
      final r = await cli(['validate', '--input', _fixture]);
      expect(r.code, 0, reason: r.err.join('\n'));
      expect(r.out.last, startsWith('OK'));
    });

    test('invalid authoring file exits 1', () async {
      final bad = File('${tmp.path}/bad.yaml')
        ..writeAsStringSync(
          File(_fixture).readAsStringSync().replaceAll(
            'bbox: "27.3,76.0,29.3,78.7"',
            'bbox: "0,0,1,1"',
          ),
        );
      final r = await cli(['validate', '--input', bad.path]);
      expect(r.code, 1);
      expect(r.err.join('\n'), contains('coordinate-outside-bbox'));
    });

    test('typo in an authoring file is an authoring error', () async {
      final bad = File('${tmp.path}/typo.yaml')
        ..writeAsStringSync(
          File(
            _fixture,
          ).readAsStringSync().replaceAll('popularity', 'popularty'),
        );
      final r = await cli(['validate', '--input', bad.path]);
      expect(r.code, 1);
      expect(r.err.join(), contains('popularty'));
    });

    test('missing input file exits 1', () async {
      final r = await cli(['validate', '--input', '${tmp.path}/none.yaml']);
      expect(r.code, 1);
      expect(r.err.join(), contains('File error'));
    });

    test('refuses TEST DATA without --allow-test-data', () async {
      final out = '${tmp.path}/metro.sqlite';
      final r = await cli(['build', '--input', _fixture, '--out', out]);
      expect(r.code, 2);
      expect(File(out).existsSync(), isFalse);
    });

    test(
      'builds the fixture to a sqlite file the app reader accepts',
      () async {
        final out = '${tmp.path}/nested/metro.sqlite';
        final r = await cli([
          'build',
          '--input',
          _fixture,
          '--out',
          out,
          '--allow-test-data',
        ]);
        expect(r.code, 0, reason: r.err.join('\n'));
        expect(r.out.last, contains('[TEST DATA]'));
        final s = DatasetReader.readFile(out);
        expect(s.isTestData, isTrue);
        expect(s.stations, hasLength(12));
      },
    );

    test('does not write a file when validation fails', () async {
      final bad = File('${tmp.path}/bad.yaml')
        ..writeAsStringSync(
          File(_fixture).readAsStringSync().replaceAll('city: "testville"', ''),
        );
      final out = '${tmp.path}/metro.sqlite';
      final r = await cli([
        'build',
        '--input',
        bad.path,
        '--out',
        out,
        '--allow-test-data',
      ]);
      expect(r.code, 1);
      expect(File(out).existsSync(), isFalse);
    });
  });

  group('real pipeline through the CLI', () {
    late Workspace ws;
    tearDown(() => ws.dispose());

    FakeTransport happy() => FakeTransport({
      'https://overpass.test/api/status': [overpassStatus()],
      'https://overpass.test/api/interpreter': [ok(MiniOsm.bytes())],
      'https://sparql.test/sparql': [ok(MiniWd.bytes())],
    });

    test(
      'fetch writes the cache and lock; build --offline then makes a draft',
      () async {
        ws = Workspace.create(writeCache: false);
        final t = happy();
        final f = await cli(['fetch'], paths: ws.paths, transport: t);
        expect(f.code, 0, reason: f.err.join());
        expect(
          f.out.join('\n'),
          allOf(contains('locked osm-overpass'), contains('locked wikidata')),
        );
        expect(
          File('${ws.root}/data/cache/sources.lock.json').existsSync(),
          isTrue,
        );
        expect(
          t.requests.every(
            (r) => r.headers['User-Agent']!.startsWith(
              'MetroMitra-data-pipeline/',
            ),
          ),
          isTrue,
        );
        expect(
          t.requests.first.headers['User-Agent'],
          isNot(contains('contact')),
        );

        final b = await cli(['build', '--offline'], paths: ws.paths);
        expect(b.code, 0, reason: b.err.join());
        expect(b.out.join('\n'), contains('stage: draft'));
        expect(
          File('${ws.root}/build/pipeline/metro.sqlite').existsSync(),
          isTrue,
        );
      },
    );

    test(
      'a contact is added to the User-Agent only when METROMITRA_CONTACT is set',
      () async {
        ws = Workspace.create(writeCache: false);
        final t = happy();
        await cli(
          ['fetch'],
          paths: ws.paths,
          transport: t,
          env: {'METROMITRA_CONTACT': 'https://example.invalid/contact'},
        );
        expect(
          t.requests.last.headers['User-Agent'],
          contains('contact: https://example.invalid/contact'),
        );
      },
    );

    test('a failed fetch exits 3 and keeps the cache', () async {
      ws = Workspace.create();
      final lock = File(
        '${ws.root}/data/cache/sources.lock.json',
      ).readAsStringSync();
      final t = FakeTransport({
        'https://overpass.test/api/status': [overpassStatus()],
        'https://overpass.test/api/interpreter': [status(504)],
      });
      final r = await cli(['fetch'], paths: ws.paths, transport: t);
      expect(r.code, 3);
      expect(
        File('${ws.root}/data/cache/sources.lock.json').readAsStringSync(),
        lock,
      );
    });

    test('build without a cache exits 4 and says to fetch', () async {
      ws = Workspace.create(writeCache: false);
      final r = await cli(['build', '--offline'], paths: ws.paths);
      expect(r.code, 4);
      expect(r.err.join(), contains('fetch'));
    });

    test('build with a corrupted cache exits 4', () async {
      ws = Workspace.create();
      final lock = SourceLock.read('${ws.root}/data/cache/sources.lock.json');
      File(
        '${ws.root}/data/cache/${lock[osmSourceId]!.file}',
      ).writeAsStringSync('corrupt');
      expect((await cli(['build'], paths: ws.paths)).code, 4);
    });

    test('blocking conflicts exit 1 and are printed', () async {
      ws = Workspace.create(
        osm: MiniOsm.bytes(
          extraTags: {
            103: {'wikidata': 'Q2000'},
            201: {'wikidata': 'Q2001'},
          },
        ),
      );
      final r = await cli(['build'], paths: ws.paths);
      expect(r.code, 1);
      expect(r.err.join('\n'), contains('BLOCKING [multiple-wikidata]'));
      expect(
        File('${ws.root}/build/pipeline/metro.sqlite').existsSync(),
        isFalse,
      );
    });

    test('--require-release on a draft exits 1', () async {
      ws = Workspace.create();
      final r = await cli(['build', '--require-release'], paths: ws.paths);
      expect(r.code, 1);
      expect(r.err.join(), contains('--require-release'));
    });

    test('diff and inspect on built datasets', () async {
      ws = Workspace.create();
      await cli(['build', '--out', '${tmp.path}/a.sqlite'], paths: ws.paths);
      ws.writeCache(MiniOsm.bytes(northHindi: true), MiniWd.bytes());
      await cli(['build', '--out', '${tmp.path}/b.sqlite'], paths: ws.paths);

      final same = await cli([
        'diff',
        '${tmp.path}/a.sqlite',
        '${tmp.path}/a.sqlite',
      ]);
      expect(same.out.single, 'No differences.');
      final d = await cli([
        'diff',
        '${tmp.path}/a.sqlite',
        '${tmp.path}/b.sqlite',
      ]);
      expect(d.code, 0);
      expect(d.out.join('\n'), contains('Stations renamed'));
      final j = await cli([
        'diff',
        '${tmp.path}/a.sqlite',
        '${tmp.path}/b.sqlite',
        '--json',
      ]);
      expect(
        (jsonDecode(j.out.join('\n')) as Map<String, Object?>)['empty'],
        isFalse,
      );
      expect((await cli(['diff', 'only-one'])).code, 64);
      File('${tmp.path}/junk.sqlite').writeAsStringSync('junk' * 200);
      expect(
        (await cli([
          'diff',
          '${tmp.path}/a.sqlite',
          '${tmp.path}/junk.sqlite',
        ])).code,
        1,
      );

      final stats = await cli(['inspect', '--input', '${tmp.path}/a.sqlite']);
      expect(
        stats.out.join('\n'),
        allOf(contains('station: 5'), contains('meta.stage = draft')),
      );
      final rows = await cli([
        'inspect',
        '--input',
        '${tmp.path}/a.sqlite',
        '--table',
        'station',
        '--limit',
        '2',
      ]);
      expect(rows.out, hasLength(2));
      expect(
        (await cli([
          'inspect',
          '--input',
          '${tmp.path}/a.sqlite',
          '--table',
          'nope',
        ])).code,
        64,
      );
      expect(
        (await cli(['inspect', '--input', '${tmp.path}/none.sqlite'])).code,
        4,
      );
    });

    test('route plans trips on a draft dataset and reports no fare', () async {
      ws = Workspace.create();
      final db = '${tmp.path}/a.sqlite';
      await cli(['build', '--out', db], paths: ws.paths);
      final snap = DatasetReader.readFile(db, mode: ValidationMode.draft);
      final line = snap.services.first;
      final stops = snap.stopsOf(line.id);
      final from = stops.first.stationId;
      final to = stops.last.stationId;

      final text = await cli(['route', from, to, '--input', db]);
      expect(text.code, 0, reason: text.err.join());
      expect(
        text.out.join('\n'),
        allOf(contains('approximate'), contains('fare: unavailable')),
      );

      final j = await cli(['route', from, to, '--input', db, '--json']);
      final parsed = jsonDecode(j.out.join('\n')) as Map<String, Object?>;
      expect(parsed['status'], 'ok');
      final first = (parsed['itineraries']! as List).first as Map;
      expect(first['assumptions'], contains('boarding_wait'));
      expect((first['fare']! as Map)['status'], 'unavailable');

      final parts = await cli(['route', '--components', '--input', db]);
      expect(parts.out.first, contains('connected part'));
    });

    test('search finds stations offline in a built dataset', () async {
      ws = Workspace.create();
      final db = '${tmp.path}/a.sqlite';
      await cli(['build', '--out', db], paths: ws.paths);
      final snap = DatasetReader.readFile(db, mode: ValidationMode.draft);
      final want = snap.stations.first;

      final text = await cli(['search', want.nameEn, '--input', db]);
      expect(text.code, 0, reason: text.err.join());
      expect(text.out.first, startsWith('1. ${want.nameEn}'));
      expect(text.out.first, contains('exact'));

      final upper = await cli([
        'search',
        want.nameEn.toUpperCase(),
        '--input',
        db,
        '--json',
      ]);
      final parsed = jsonDecode(upper.out.join()) as Map<String, Object?>;
      final first = (parsed['results']! as List).first as Map;
      expect(first['id'], want.id);
      expect(first['name_en'], want.nameEn);
      expect(first['name_hi'], want.nameHi, reason: 'NULL stays NULL');
      expect((first['provenance']! as Map)['source'], isNotEmpty);
      expect((first['match']! as Map)['tier'], 'exact');
      expect(first['lines'], isNotEmpty);

      final none = await cli(['search', 'qqqqqqqq', '--input', db]);
      expect(none.code, 0);
      expect(none.out.single, 'No results.');

      final stOnly = await cli(['search', 'line', '--input', db, '--stations']);
      expect(stOnly.out.join(), isNot(contains('LINE ')));
      final lnOnly = await cli(['search', 'line', '--input', db, '--lines']);
      expect(lnOnly.out.join(), contains('LINE '));
    });

    test('search --self-check passes on a built dataset', () async {
      ws = Workspace.create();
      final db = '${tmp.path}/a.sqlite';
      await cli(['build', '--out', db], paths: ws.paths);
      final r = await cli(['search', '--self-check', '--input', db]);
      expect(r.code, 0, reason: r.err.join());
      expect(r.out.single, startsWith('OK'));
    });

    test('search usage errors', () async {
      ws = Workspace.create();
      final db = '${tmp.path}/a.sqlite';
      await cli(['build', '--out', db], paths: ws.paths);
      expect((await cli(['search', '--input', db])).code, 64);
      expect((await cli(['search', 'a', 'b', '--input', db])).code, 64);
      expect((await cli(['search', 'a', '--input', '${tmp.path}/x'])).code, 4);
    });

    test(
      'route failures: unknown station, bad usage, missing dataset',
      () async {
        ws = Workspace.create();
        final db = '${tmp.path}/a.sqlite';
        await cli(['build', '--out', db], paths: ws.paths);
        final unknown = await cli(['route', 'nope', 'nada', '--input', db]);
        expect(unknown.code, 1);
        expect(unknown.err.join(), contains('unknownStation'));
        expect((await cli(['route', 'one', '--input', db])).code, 64);
        expect(
          (await cli(['route', 'a', 'b', '--input', '${tmp.path}/x'])).code,
          4,
        );
      },
    );

    test(
      'validate --draft accepts a draft sqlite; release rules reject it',
      () async {
        ws = Workspace.create();
        await cli(['build', '--out', '${tmp.path}/a.sqlite'], paths: ws.paths);
        expect(
          (await cli([
            'validate',
            '--input',
            '${tmp.path}/a.sqlite',
            '--draft',
          ])).code,
          0,
        );
        expect(
          (await cli(['validate', '--input', '${tmp.path}/a.sqlite'])).code,
          1,
        );
      },
    );
  });
}
