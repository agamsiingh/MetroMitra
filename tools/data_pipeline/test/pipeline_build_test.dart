import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/data_pipeline.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:test/test.dart';

import 'support/support.dart';

const _cur = '''
    reason: "TEST reason"
    source: mitra-curated
    verified_on: "2026-10-01"
''';

/// Completes everything the mini network lacks for a *release*.
const _completeOverlay =
    '''
operators:
  - osm_operator: "TEST Operator"
    id: test-op
    name_hi: "टेस्ट ऑपरेटर"
$_cur
stations:
  - id: test-north
    name_hi: "टेस्ट नॉर्थ"
$_cur
''';

void main() {
  late Workspace ws;
  tearDown(() => ws.dispose());

  BuildOutcome build({bool requireRelease = false}) => buildDataset(
    ws.paths,
    requireRelease: requireRelease,
    now: DateTime.utc(2026, 10, 5),
  );

  group('draft vs release', () {
    test('incomplete data (unknown Hindi names) builds a valid DRAFT', () {
      ws = Workspace.create();
      final o = build();
      expect(o.stage, 'draft');
      expect(o.ok, isTrue);
      final db = DatasetReader.readFile(
        '${ws.root}/build/pipeline/metro.sqlite',
        mode: ValidationMode.draft,
      );
      expect(db.isDraft, isTrue);
      expect(db.meta['stage'], 'draft');
      expect(db.stations, hasLength(5));
    });

    test('the app (release rules) refuses a draft dataset', () {
      ws = Workspace.create();
      build();
      expect(
        () => DatasetReader.readFile('${ws.root}/build/pipeline/metro.sqlite'),
        throwsA(
          isA<DatasetException>().having(
            (e) => e.report!.hasError('draft-dataset'),
            'draft',
            isTrue,
          ),
        ),
      );
    });

    test('a complete, curated dataset reaches stage RELEASE', () {
      ws = Workspace.create(overlay: _completeOverlay);
      final o = build();
      expect(o.stage, 'release', reason: '${o.report['validation']}');
      final db = DatasetReader.readFile(
        '${ws.root}/build/pipeline/metro.sqlite',
      );
      expect(db.meta.containsKey('stage'), isTrue);
      expect(db.meta['stage'], 'release');
      expect(db.operators.single.nameHi, 'टेस्ट ऑपरेटर');
    });

    test('--require-release refuses to write a draft', () {
      ws = Workspace.create();
      final o = build(requireRelease: true);
      expect(o.ok, isFalse);
      expect(
        File('${ws.root}/build/pipeline/metro.sqlite').existsSync(),
        isFalse,
      );
    });
  });

  group('blocking conflicts', () {
    test(
      'an unresolved error conflict writes NO dataset but still writes the report',
      () {
        ws = Workspace.create(
          osm: MiniOsm.bytes(
            extraTags: {
              103: {'wikidata': 'Q2000'},
              201: {'wikidata': 'Q2001'},
            },
          ),
        );
        final o = build();
        expect(o.stage, 'failed');
        expect(o.ok, isFalse);
        expect(
          File('${ws.root}/build/pipeline/metro.sqlite').existsSync(),
          isFalse,
        );
        final report =
            jsonDecode(
                  File(
                    '${ws.root}/build/pipeline/build-report.json',
                  ).readAsStringSync(),
                )
                as Map;
        expect((report['conflicts'] as Map)['blocking'], 1);
        expect(report['output'], isNull);
      },
    );

    test('a failed build never replaces an existing good dataset', () {
      ws = Workspace.create(overlay: _completeOverlay);
      build();
      final out = File('${ws.root}/build/pipeline/metro.sqlite');
      final before = out.readAsBytesSync();
      ws.writeCache(
        MiniOsm.bytes(
          extraTags: {
            103: {'wikidata': 'Q2000'},
            201: {'wikidata': 'Q2001'},
          },
        ),
        MiniWd.bytes(),
      );
      final o = build();
      expect(o.stage, 'failed');
      expect(out.readAsBytesSync(), before);
    });

    test('a curated resolution unblocks it', () {
      ws = Workspace.create(
        osm: MiniOsm.bytes(
          extraTags: {
            103: {'wikidata': 'Q2000'},
            201: {'wikidata': 'Q2001'},
          },
        ),
        overlay:
            '''
resolutions:
  - conflict: "multiple-wikidata|cluster:test-north@test-alpha-line"
    accept: true
$_cur
''',
      );
      expect(build().ok, isTrue);
    });
  });

  group('report', () {
    test(
      'lists inputs with hashes, versions and licences; conflicts; overrides',
      () {
        ws = Workspace.create(overlay: _completeOverlay);
        final o = build();
        final r = o.report;
        final inputs = r['inputs']! as Map;
        final osm = inputs['osm-overpass'] as Map;
        expect(osm['sha256'], hasLength(64));
        expect(osm['source_version'], '2026-10-05T09:59:00Z');
        expect(osm['retrieved_at'], '2026-10-05T10:00:00Z');
        expect(osm['license'], 'ODbL-1.0');
        expect(osm['attribution'], contains('OpenStreetMap'));
        expect((inputs['wikidata'] as Map)['license'], 'CC0-1.0');
        expect((inputs['curated-overlay'] as Map)['sha256'], hasLength(64));
        expect((inputs['curated-overlay'] as Map)['stations'], 1);
        expect(r['overrides'], hasLength(1));
        final conflicts = r['conflicts']! as Map;
        expect(conflicts['by_kind'], {'interchange-candidate': 1});
        expect((r['output']! as Map)['sha256'], o.outputSha256);
      },
    );

    test('has a routing section: connectivity and unknown-data counts', () {
      ws = Workspace.create();
      final r = build().report['routing']! as Map;
      expect(r['components'], isA<int>());
      expect(r['component_sizes'], isA<List<Object?>>());
      expect(r['edges_without_travel_time'], r['edges']);
      expect(r['fare_systems'], 0);
      expect(r['timings'], 0);
      expect((r['time_model']! as Map)['id'], 'fallback-v1');
      expect(r['time_model_status'], contains('unapproved'));
    });

    test('has a search section: counts and a clean self-check', () {
      ws = Workspace.create();
      final s = build().report['search']! as Map;
      expect(s['searchable_entities'], greaterThan(0));
      expect(s['self_check_problems'], 0);
      expect(s['stations_without_hindi_name'], isA<int>());
    });

    test('is canonical JSON (sorted keys, trailing newline)', () {
      ws = Workspace.create();
      build();
      final text = File(
        '${ws.root}/build/pipeline/build-report.json',
      ).readAsStringSync();
      expect(text.endsWith('\n'), isTrue);
      expect(canonicalJson(jsonDecode(text)), text);
    });
  });

  group('deterministic output', () {
    test('same locked inputs -> byte-identical sqlite and report', () {
      ws = Workspace.create(overlay: _completeOverlay);
      final a = build();
      final bytesA = File(
        '${ws.root}/build/pipeline/metro.sqlite',
      ).readAsBytesSync();
      final reportA = File(
        '${ws.root}/build/pipeline/build-report.json',
      ).readAsStringSync();
      final b = build();
      expect(
        File('${ws.root}/build/pipeline/metro.sqlite').readAsBytesSync(),
        bytesA,
      );
      expect(
        File('${ws.root}/build/pipeline/build-report.json').readAsStringSync(),
        reportA,
      );
      expect(a.outputSha256, b.outputSha256);
    });

    test('does not depend on the wall clock', () {
      ws = Workspace.create();
      final a = buildDataset(ws.paths, now: DateTime.utc(2000));
      final b = buildDataset(ws.paths, now: DateTime.utc(2030, 5, 5));
      expect(a.outputSha256, b.outputSha256);
    });

    test('built_at and version come from the lock, not from "now"', () {
      ws = Workspace.create();
      final o = build();
      expect(o.snapshot!.meta['built_at'], '2026-10-05T11:00:00Z');
      expect(o.snapshot!.datasetVersion, '2026.10.0');
    });

    test('a different locked input gives a different file', () {
      ws = Workspace.create();
      final a = build().outputSha256;
      ws.writeCache(MiniOsm.bytes(northHindi: true), MiniWd.bytes());
      expect(build().outputSha256, isNot(a));
    });
  });

  group(
    'missing, stale or corrupt inputs fail clearly (no dataset written)',
    () {
      test('no cache at all', () {
        ws = Workspace.create(writeCache: false);
        expect(
          build,
          throwsA(
            isA<InputException>().having(
              (e) => e.message,
              'm',
              contains('fetch'),
            ),
          ),
        );
        expect(
          File('${ws.root}/build/pipeline/metro.sqlite').existsSync(),
          isFalse,
        );
      });

      test('lock without one of the sources', () {
        ws = Workspace.create();
        final lock = SourceLock.read('${ws.root}/data/cache/sources.lock.json');
        SourceLock({
          osmSourceId: lock[osmSourceId]!,
        }).write('${ws.root}/data/cache/sources.lock.json');
        expect(
          build,
          throwsA(
            isA<InputException>().having(
              (e) => e.message,
              'm',
              contains('wikidata'),
            ),
          ),
        );
      });

      test('cache file modified after fetch', () {
        ws = Workspace.create();
        final lock = SourceLock.read('${ws.root}/data/cache/sources.lock.json');
        final f = File('${ws.root}/data/cache/${lock[osmSourceId]!.file}');
        f.writeAsBytesSync(f.readAsBytesSync()..[5] ^= 0xFF);
        expect(
          build,
          throwsA(
            isA<InputException>().having(
              (e) => e.message,
              'm',
              contains('does not match'),
            ),
          ),
        );
      });

      test('cache file deleted', () {
        ws = Workspace.create();
        final lock = SourceLock.read('${ws.root}/data/cache/sources.lock.json');
        File(
          '${ws.root}/data/cache/${lock[wikidataSourceId]!.file}',
        ).deleteSync();
        expect(
          build,
          throwsA(
            isA<InputException>().having(
              (e) => e.message,
              'm',
              contains('missing'),
            ),
          ),
        );
      });

      test('query changed since the cache was fetched', () {
        ws = Workspace.create();
        File(
          '${ws.root}/data/sources/queries/osm.overpassql',
        ).writeAsStringSync('[out:json]; something-else;');
        expect(
          build,
          throwsA(
            isA<InputException>().having(
              (e) => e.message,
              'm',
              contains('query file changed'),
            ),
          ),
        );
      });

      test('corrupt lock file', () {
        ws = Workspace.create();
        File(
          '${ws.root}/data/cache/sources.lock.json',
        ).writeAsStringSync('garbage');
        expect(build, throwsA(isA<LockException>()));
      });

      test(
        'cached data that is not valid OSM JSON (hash matches, content corrupt)',
        () {
          ws = Workspace.create(osm: utf8.encode('<html>not json</html>'));
          expect(build, throwsA(isA<SourceFormatException>()));
        },
      );

      test('missing config', () {
        ws = Workspace.create();
        File('${ws.root}/data/sources/sources.yaml').deleteSync();
        expect(build, throwsA(isA<ConfigException>()));
      });

      test('invalid overlay', () {
        ws = Workspace.create(overlay: 'gates: []');
        expect(build, throwsA(isA<OverlayException>()));
      });

      test('a missing overlay file means no curation, not an error', () {
        ws = Workspace.create();
        File('${ws.root}/data/curated/overlays.yaml').deleteSync();
        expect(build().ok, isTrue);
      });
    },
  );

  group('written dataset', () {
    test(
      'contains no gates, platforms, facilities, parking, fares or timings',
      () {
        ws = Workspace.create(overlay: _completeOverlay);
        build();
        final db = DatasetReader.readFile(
          '${ws.root}/build/pipeline/metro.sqlite',
        );
        for (final rows in [
          db.gates,
          db.gateLandmarks,
          db.platforms,
          db.facilities,
          db.accessibility,
          db.fareSystems,
          db.fareSlabs,
          db.fareDiscounts,
          db.fareOverrides,
          db.timings,
          db.walkLinks,
        ]) {
          expect(rows, isEmpty);
        }
        expect(db.edges.every((e) => e.travelS == null), isTrue);
      },
    );

    test('carries provenance: sources with hashes and per-field origins', () {
      ws = Workspace.create();
      build();
      final db = DatasetReader.readFile(
        '${ws.root}/build/pipeline/metro.sqlite',
        mode: ValidationMode.draft,
      );
      expect(
        db.sources.map((s) => s.id),
        unorderedEquals([
          'osm-overpass',
          'wikidata',
          'mitra-curated',
          'mitra-derived',
        ]),
      );
      expect(
        db.sources.firstWhere((s) => s.id == 'osm-overpass').sha256,
        hasLength(64),
      );
      expect(db.origins, isNotEmpty);
    });
  });
}
