import 'package:data_pipeline/data_pipeline.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:test/test.dart';

import 'support/support.dart';

const _cur = '''
    reason: "TEST reason"
    source: mitra-curated
    verified_on: "2026-10-01"
''';

final _cfg = testConfig();

MergeResult merge({
  List<Map<String, Object?>>? elements,
  List<int>? wd,
  String overlay = '',
  PipelineConfig? config,
}) {
  final c = config ?? _cfg;
  final osmBytes = overpassBytes(elements ?? MiniOsm.elements());
  final wdBytes = wd ?? MiniWd.bytes();
  return mergeSources(
    osm: normalizeOsm(osmBytes, network: 'Test Net'),
    wikidata: normalizeWikidata(wdBytes, c.normalization),
    overlay: Overlay.parse(overlay),
    config: c,
    lock: testLock(c, osmBytes, wdBytes),
  );
}

List<Map<String, Object?>> withTags(Map<int, Map<String, String>> extra) =>
    MiniOsm.elements(extraTags: extra);

Conflict? conflict(MergeResult r, String kind) =>
    r.conflicts.where((c) => c.kind == kind).firstOrNull;

Origin? origin(
  MergeResult r,
  String entity,
  String id,
  String field, [
  String? source,
]) => r.snapshot.origins
    .where(
      (o) =>
          o.entity == entity &&
          o.entityId == id &&
          o.field == field &&
          (source == null || o.sourceId == source),
    )
    .firstOrNull;

void main() {
  group('baseline mini network', () {
    final r = merge();
    final s = r.snapshot;

    test('produces the expected stations, lines and services', () {
      expect(s.stations.map((x) => x.id), [
        'test-central',
        'test-east-test-alpha-line',
        'test-east-test-beta-line',
        'test-north',
        'test-west',
      ]);
      expect(s.lines.map((l) => l.id), ['test-alpha-line', 'test-beta-line']);
      expect(s.services.map((x) => x.id), [
        'test-alpha-line-test-central-test-north',
        'test-beta-line-test-central-test-west',
      ]);
    });

    test(
      'opposite-direction relations fold into ONE service in canonical order',
      () {
        final stops = s
            .stopsOf('test-alpha-line-test-central-test-north')
            .map((x) => x.stationId);
        expect(stops, [
          'test-central',
          'test-east-test-alpha-line',
          'test-north',
        ]);
      },
    );

    test('reports only the same-name interchange candidate; nothing blocks', () {
      expect(r.conflicts.map((c) => c.kind), ['interchange-candidate']);
      expect(r.blocking, isEmpty);
      final c = r.conflicts.single;
      expect(
        c.id,
        'interchange-candidate|test-east-test-alpha-line+test-east-test-beta-line',
      );
      expect(
        c.candidates.keys,
        containsAll(['test-east@test-alpha-line', 'test-east@test-beta-line']),
      );
      expect(c.message, contains('NOT merged'));
    });

    test('same-name stations without a shared id are NOT merged', () {
      expect(s.linesAt('test-east-test-alpha-line').map((l) => l.id), [
        'test-alpha-line',
      ]);
      expect(s.linesAt('test-east-test-beta-line').map((l) => l.id), [
        'test-beta-line',
      ]);
    });

    test(
      'a shared Wikidata id merges stops of different lines into one interchange',
      () {
        expect(
          s.linesAt('test-central').map((l) => l.id),
          unorderedEquals(['test-alpha-line', 'test-beta-line']),
        );
        expect(r.stats['interchange_stations'], 1);
        expect(
          origin(r, 'station', 'test-central', 'merge')!.status,
          OriginStatus.derived,
        );
        expect(
          origin(r, 'station', 'test-central', 'merge')!.detail,
          contains('Q1000'),
        );
      },
    );

    test('merged interchange gets transfer rows with UNKNOWN walking time', () {
      final t = s.transfersAt('test-central');
      expect(t, hasLength(2));
      for (final x in t) {
        expect(x.walkM, isNull);
        expect(x.walkS, isNull);
        expect(x.stepFree, isNull);
        expect(x.provenance.sourceId, derivedSourceId);
      }
    });

    test(
      'edges: both directions, straight-line metres, travel time UNKNOWN',
      () {
        expect(s.edges, hasLength(8));
        final e = s.edges.firstWhere(
          (x) =>
              x.id.endsWith('test-central>test-east-test-alpha-line') &&
              x.serviceId.startsWith('test-alpha'),
        );
        expect(e.distanceM, greaterThan(900));
        expect(e.distanceM, lessThan(1200));
        expect(s.edges.every((x) => x.travelS == null), isTrue);
        expect(
          s.edges.every((x) => x.provenance.confidence == Confidence.derived),
          isTrue,
        );
      },
    );

    test('service stop distances accumulate and start at 0', () {
      final stops = s.stopsOf('test-alpha-line-test-central-test-north');
      expect(stops.first.distFromStartM, 0);
      expect(stops[1].distFromStartM, greaterThan(0));
      expect(stops[2].distFromStartM, greaterThan(stops[1].distFromStartM));
    });

    test(
      'NOTHING is invented: no gates/platforms/facilities/accessibility/fares/timings/walk links',
      () {
        expect(s.gates, isEmpty);
        expect(s.gateLandmarks, isEmpty);
        expect(s.platforms, isEmpty);
        expect(s.facilities, isEmpty);
        expect(s.accessibility, isEmpty);
        expect(s.fareSystems, isEmpty);
        expect(s.fareSlabs, isEmpty);
        expect(s.fareDiscounts, isEmpty);
        expect(s.fareOverrides, isEmpty);
        expect(s.timings, isEmpty);
        expect(s.walkLinks, isEmpty);
        expect(s.operators.every((o) => o.fareSystemId == null), isTrue);
      },
    );

    test('Hindi names come only from sources; unknown stays null', () {
      expect(s.station('test-central')!.nameHi, 'टेस्ट सेंट्रल');
      expect(s.station('test-north')!.nameHi, isNull);
      expect(r.stats['stations_without_hindi_name'], 1);
      expect(s.operators.single.nameHi, isNull);
    });

    test(
      'line data: colour upper-cased, contrast text derived, Hindi label from Wikidata',
      () {
        final l = s.line('test-alpha-line')!;
        expect(l.colorHex, '#C62828');
        expect(l.textColorHex, '#FFFFFF');
        expect(l.nameHi, 'टेस्ट अल्फा लाइन');
        expect(l.shortName, 'A');
        expect(l.status, OperatingStatus.open);
        expect(s.lines.map((x) => x.sort), [1, 2]);
      },
    );

    test('operator comes from the OSM tag', () {
      expect(s.operators.single.id, 'test-operator');
      expect(s.operators.single.nameEn, 'TEST Operator');
      expect(s.line('test-alpha-line')!.operatorId, 'test-operator');
    });

    test('station codes are kept per line', () {
      final codes = {
        for (final x in s.stationLines.where(
          (x) => x.stationId == 'test-central',
        ))
          x.lineId: x.stationCode,
      };
      expect(codes, {'test-alpha-line': 'A1', 'test-beta-line': 'B1'});
    });

    test('meta is deterministic and carries attribution', () {
      expect(s.meta['built_at'], '2026-10-05T11:00:00Z');
      expect(s.meta['dataset_version'], '2026.10.0');
      expect(s.meta['schema_version'], '$currentSchemaVersion');
      expect(s.meta['city'], 'testville');
      expect(
        s.meta['attribution'],
        allOf(
          contains('OpenStreetMap'),
          contains('Wikidata'),
          contains('not affiliated with DMRC'),
        ),
      );
    });

    test('the draft result validates in draft mode', () {
      final report = validateSnapshot(s, mode: ValidationMode.draft);
      expect(report.errors, isEmpty, reason: report.toString());
    });
  });

  group('provenance', () {
    final r = merge();
    final s = r.snapshot;

    test(
      'every source referenced by a fact or origin exists, with licence/version/hash',
      () {
        final ids = s.sources.map((x) => x.id).toSet();
        expect(ids, {
          osmSourceId,
          wikidataSourceId,
          curatedSourceId,
          derivedSourceId,
        });
        for (final p in [
          ...s.stations.map((x) => x.provenance),
          ...s.edges.map((x) => x.provenance),
          ...s.transfers.map((x) => x.provenance),
        ]) {
          expect(ids, contains(p.sourceId));
        }
        for (final o in s.origins) {
          expect(ids, contains(o.sourceId));
        }
        final osm = s.sources.firstWhere((x) => x.id == osmSourceId);
        expect(osm.license, 'ODbL-1.0');
        expect(osm.version, '2026-10-05T09:59:00Z');
        expect(osm.retrievedAt, '2026-10-05T10:00:00Z');
        expect(osm.sha256, hasLength(64));
        expect(osm.notes, contains('OpenStreetMap'));
        final wd = s.sources.firstWhere((x) => x.id == wikidataSourceId);
        expect(wd.license, 'CC0-1.0');
        expect(wd.retrievedAt, '2026-10-05T11:00:00Z');
      },
    );

    test('every station has origin rows with external ids', () {
      for (final st in s.stations) {
        final rec = origin(r, 'station', st.id, 'record')!;
        expect(rec.sourceId, osmSourceId);
        expect(rec.status, OriginStatus.imported);
        expect(rec.externalId, startsWith('node/'));
        expect(origin(r, 'station', st.id, 'name_en'), isNotNull);
        expect(origin(r, 'station', st.id, 'lat_lng'), isNotNull);
      }
      expect(
        origin(r, 'station', 'test-central', 'record')!.externalId,
        'node/101;node/203;node/301;node/403',
      );
      expect(
        origin(r, 'station', 'test-central', 'wikidata')!.externalId,
        'Q1000',
      );
      expect(
        origin(r, 'station', 'test-central', 'lat_lng')!.status,
        OriginStatus.derived,
      );
      expect(
        origin(r, 'station', 'test-central', 'lat_lng')!.detail,
        contains('4 stop nodes'),
      );
    });

    test(
      'line, service and operator origins record relation ids and derivations',
      () {
        expect(
          origin(r, 'line', 'test-alpha-line', 'record')!.externalId,
          'relation/11;relation/12',
        );
        expect(
          origin(r, 'line', 'test-alpha-line', 'wikidata')!.externalId,
          'Q9001',
        );
        expect(
          origin(r, 'line', 'test-alpha-line', 'text_color_hex')!.status,
          OriginStatus.derived,
        );
        expect(
          origin(r, 'line', 'test-alpha-line', 'name_hi')!.sourceId,
          wikidataSourceId,
        );
        expect(
          origin(
            r,
            'line_service',
            'test-alpha-line-test-central-test-north',
            'record',
          )!.externalId,
          'relation/11;relation/12',
        );
        expect(
          origin(r, 'operator', 'test-operator', 'record')!.sourceId,
          osmSourceId,
        );
      },
    );

    test(
      'origin rows are unique per (entity, id, field, source) and validate',
      () {
        expect(
          s.origins.map((o) => o.key).toSet(),
          hasLength(s.origins.length),
        );
        expect(
          validateSnapshot(
            s,
            mode: ValidationMode.draft,
          ).errors.where((e) => e.code.contains('origin')),
          isEmpty,
        );
      },
    );
  });

  group('Wikidata cross-check', () {
    test(
      'fills an UNKNOWN Hindi name from Wikidata and marks it normalized',
      () {
        final wd = sparqlBytes([
          wdRow(
            'Q1000',
            en: 'TEST Central',
            hi: 'टेस्ट सेंट्रल',
            lat: 28.6001,
            lng: 77.1001,
          ),
          wdRow(
            'Q2000',
            en: 'TEST North metro station',
            hi: 'टेस्ट नॉर्थ मेट्रो स्टेशन',
          ),
        ]);
        final r = merge(
          elements: withTags({
            103: {'wikidata': 'Q2000'},
            201: {'wikidata': 'Q2000'},
          }),
          wd: wd,
        );
        expect(r.snapshot.station('test-north')!.nameHi, 'टेस्ट नॉर्थ');
        final o = origin(r, 'station', 'test-north', 'name_hi')!;
        expect(o.sourceId, wikidataSourceId);
        expect(o.status, OriginStatus.normalized);
        expect(o.externalId, 'Q2000');
        expect(r.stats['stations_without_hindi_name'], 0);
      },
    );

    test(
      'differing values are REPORTED with both candidates; OSM is kept by default',
      () {
        final r = merge(
          wd: MiniWd.bytes(
            centralEn: 'TEST Centrale',
            centralHi: 'टेस्ट केंद्र',
            centralLat: 28.7,
            centralLng: 77.2,
          ),
        );
        expect(r.snapshot.station('test-central')!.nameEn, 'TEST Central');
        expect(r.snapshot.station('test-central')!.nameHi, 'टेस्ट सेंट्रल');
        final en = conflict(r, 'name-en-mismatch')!;
        expect(en.id, 'name-en-mismatch|station:test-central|name_en');
        expect(en.candidates, {
          'osm': 'TEST Central',
          'wikidata': 'TEST Centrale',
        });
        expect(en.severity, ConflictSeverity.warning);
        expect(en.resolved, isFalse);
        expect(conflict(r, 'name-hi-mismatch')!.candidates, {
          'osm': 'टेस्ट सेंट्रल',
          'wikidata': 'टेस्ट केंद्र',
        });
        final geo = conflict(r, 'coordinate-mismatch')!;
        expect(geo.candidates['wikidata'], '28.7,77.2');
        expect(geo.message, contains('m apart'));
      },
    );

    test('small coordinate differences are not conflicts', () {
      final r = merge(
        wd: MiniWd.bytes(centralLat: 28.6003, centralLng: 77.1003),
      );
      expect(conflict(r, 'coordinate-mismatch'), isNull);
    });

    test(
      'an OSM link to a Wikidata item missing from the download is reported',
      () {
        final r = merge(wd: sparqlBytes([wdRow('Q7777', en: 'x')]));
        expect(
          conflict(r, 'wikidata-entity-missing')!.subject,
          'station:test-central',
        );
      },
    );

    test('stations are never linked to Wikidata by name matching', () {
      final wd = sparqlBytes([
        wdRow('Q5555', en: 'TEST North metro station', hi: 'टेस्ट नॉर्थ'),
      ]);
      final r = merge(wd: wd);
      expect(r.snapshot.station('test-north')!.nameHi, isNull);
      expect(r.stats['stations_without_wikidata_ids'], contains('test-north'));
    });

    test('works without any Wikidata data (optional source)', () {
      final osmBytes = overpassBytes(MiniOsm.elements());
      final r = mergeSources(
        osm: normalizeOsm(osmBytes, network: 'Test Net'),
        wikidata: null,
        overlay: Overlay.empty,
        config: _cfg,
        lock: testLock(_cfg, osmBytes, MiniWd.bytes()),
      );
      expect(r.snapshot.stations, hasLength(5));
      expect(r.snapshot.line('test-alpha-line')!.nameHi, isNull);
    });
  });

  group('conflicts that block the build until a human decides', () {
    test('two Wikidata ids in one station', () {
      final r = merge(
        elements: withTags({
          103: {'wikidata': 'Q2000'},
          201: {'wikidata': 'Q2001'},
        }),
      );
      final c = conflict(r, 'multiple-wikidata')!;
      expect(c.severity, ConflictSeverity.error);
      expect(c.blocking, isTrue);
      expect(c.candidates.keys, ['Q2000', 'Q2001']);
      expect(r.blocking, contains(c));
    });

    test('same-name stops of one line far apart', () {
      final els = MiniOsm.elements();
      final moved = [
        for (final e in els)
          if (e['id'] == 201) osmNode(201, 'TEST North', 28.70, 77.30) else e,
      ];
      final r = merge(elements: moved);
      expect(conflict(r, 'cluster-spread')!.blocking, isTrue);
    });

    test('a stop node missing from the download', () {
      final els = [
        for (final e in MiniOsm.elements())
          if (e['id'] != 102) e,
      ];
      final r = merge(elements: els);
      expect(conflict(r, 'source-missing-node')!.blocking, isTrue);
      expect(conflict(r, 'source-missing-node')!.message, contains('102'));
    });

    test('a line without any usable colour', () {
      final els = [
        for (final e in MiniOsm.elements())
          if (e['type'] == 'relation' && (e['id'] == 11 || e['id'] == 12))
            osmRelation(
              e['id']! as int,
              'TEST Alpha Line (x)',
              [
                for (final m in (e['members']! as List).where(
                  (m) => (m as Map)['type'] == 'node',
                ))
                  (m as Map)['ref']! as int,
              ],
              colour: 'red',
              lineQid: 'Q9001',
            )
          else
            e,
      ];
      final r = merge(elements: els);
      expect(conflict(r, 'line-colour-missing')!.blocking, isTrue);
    });

    test('two OSM lines producing the same id', () {
      final els = [
        ...MiniOsm.elements(),
        osmRelation(
          31,
          'TEST Alpha Line (clone)',
          [101, 102],
          ref: 'Z',
          lineQid: 'Q9999',
        ),
      ];
      expect(
        conflict(merge(elements: els), 'line-id-collision')!.blocking,
        isTrue,
      );
    });

    test('the same Wikidata id on two stations of one line is not merged', () {
      final r = merge(
        elements: withTags({
          102: {'wikidata': 'Q1000'},
          202: {'wikidata': 'Q1000'},
        }),
      );
      expect(conflict(r, 'wikidata-same-line-duplicate')!.blocking, isTrue);
    });
  });

  group('lower-severity data conflicts are reported (warnings)', () {
    test('different Hindi names on stop nodes of one station', () {
      final r = merge(
        elements: withTags({
          202: {'name:hi': 'टेस्ट पूर्व'},
        }),
      );
      final c = conflict(r, 'name-hi-inconsistent')!;
      expect(c.severity, ConflictSeverity.warning);
      expect(c.candidates.values, containsAll(['टेस्ट ईस्ट', 'टेस्ट पूर्व']));
    });

    test('inconsistent line colours', () {
      final els = [
        for (final e in MiniOsm.elements())
          if (e['id'] == 12)
            osmRelation(
              12,
              'TEST Alpha Line (b)',
              [201, 202, 203],
              colour: '#00FF00',
              lineQid: 'Q9001',
            )
          else
            e,
      ];
      expect(
        conflict(merge(elements: els), 'line-colour-inconsistent'),
        isNotNull,
      );
    });

    test('duplicate station codes are reported and left unknown (null)', () {
      final r = merge(
        elements: withTags({
          102: {'ref': 'A1'},
          202: {'ref': 'A1'},
        }),
      );
      final c = conflict(r, 'station-code-duplicate')!;
      expect(
        c.candidates.keys,
        containsAll(['test-central', 'test-east-test-alpha-line']),
      );
      final codes = r.snapshot.stationLines
          .where((x) => x.lineId == 'test-alpha-line')
          .map((x) => x.stationCode);
      expect(codes, everyElement(isNull));
    });

    test('a route that revisits a station is kept and reported', () {
      final els = [
        ...MiniOsm.elements(),
        osmRelation(
          41,
          'TEST Alpha Line (loop-ish)',
          [101, 102, 103, 102],
          colour: '#C62828',
          lineQid: 'Q9001',
        ),
      ];
      final r = merge(elements: els);
      final c = conflict(r, 'service-revisits-station')!;
      expect(c.message, contains('test-east-test-alpha-line'));
    });

    test('same name but far apart is only a name collision', () {
      final r = merge(config: testConfig(mergeCandidateRadiusM: 10));
      expect(conflict(r, 'name-collision'), isNotNull);
      expect(conflict(r, 'interchange-candidate'), isNull);
    });

    test('candidate detection ignores a trailing "(... Line)" qualifier', () {
      final els = [
        for (final e in MiniOsm.elements())
          if (e['type'] == 'node' &&
              {301, 302, 303, 401, 402, 403}.contains(e['id']))
            osmNode(
              e['id']! as int,
              '${(e['tags']! as Map)['name']} (Beta Line)',
              e['lat']! as double,
              e['lon']! as double,
              tags: {
                for (final t in (e['tags']! as Map).entries)
                  if (t.key != 'name') '${t.key}': '${t.value}',
              },
            )
          else
            e,
      ];
      final r = merge(elements: els);
      // "TEST East" (alpha) vs "TEST East (Beta Line)" are still candidates.
      expect(
        r.conflicts.where((c) => c.kind == 'interchange-candidate'),
        isNotEmpty,
      );
      // ... but display names keep the OSM text.
      expect(
        r.snapshot.stations.map((s) => s.nameEn),
        contains('TEST East (Beta Line)'),
      );
    });
  });

  group('curated overlays', () {
    test('a curated merge joins clusters by explicit decision', () {
      final r = merge(
        overlay:
            '''
station_merges:
  - id: test-east
    members: ["test-east@test-alpha-line", "test-east@test-beta-line"]
$_cur
''',
      );
      expect(r.snapshot.station('test-east'), isNotNull);
      expect(
        r.snapshot.linesAt('test-east').map((l) => l.id),
        unorderedEquals(['test-alpha-line', 'test-beta-line']),
      );
      expect(r.snapshot.stations, hasLength(4));
      expect(r.snapshot.transfersAt('test-east'), hasLength(2));
      final o = origin(r, 'station', 'test-east', 'merge')!;
      expect(o.sourceId, curatedSourceId);
      expect(o.status, OriginStatus.curated);
      expect(
        r.conflicts.where((c) => c.kind == 'interchange-candidate'),
        isEmpty,
      );
    });

    test(
      'a curated merge records its audit trail and verifies the transfers',
      () {
        final r = merge(
          overlay:
              '''
station_merges:
  - id: test-east
    members: ["test-east@test-alpha-line", "test-east@test-beta-line"]
$_cur
''',
        );
        final o = origin(r, 'station', 'test-east', 'merge')!;
        expect(o.detail, contains('test-east@test-alpha-line'));
        expect(o.detail, contains('TEST reason'));
        expect(o.detail, contains('2026-10-01'));
        for (final tr in r.snapshot.transfersAt('test-east')) {
          expect(tr.provenance.sourceId, curatedSourceId);
          expect(tr.provenance.confidence, Confidence.verified);
          expect(tr.provenance.verifiedOn, '2026-10-01');
          expect(tr.walkS, isNull, reason: 'walk time stays unknown');
          expect(tr.walkM, isNull);
          expect(tr.stepFree, isNull);
        }
      },
    );

    test('transfers from a Wikidata-only merge stay merely derived', () {
      final r = merge(
        elements: withTags({
          103: {'wikidata': 'Q2000'},
          201: {'wikidata': 'Q2000'},
        }),
      );
      expect(r.snapshot.transfers, isNotEmpty);
      for (final tr in r.snapshot.transfers) {
        expect(tr.provenance.confidence, isNot(Confidence.verified));
      }
    });

    test(
      'merging unknown clusters, or two clusters of one line, is an error',
      () {
        final unknown = merge(
          overlay:
              'station_merges:\n  - id: x\n    members: ["a@b", "c@d"]\n$_cur',
        );
        expect(conflict(unknown, 'overlay-unknown-cluster')!.blocking, isTrue);
        final sameLine = merge(
          overlay:
              'station_merges:\n  - id: x\n    members: ["test-east@test-alpha-line", "test-north@test-alpha-line"]\n$_cur',
        );
        expect(conflict(sameLine, 'overlay-merge-same-line')!.blocking, isTrue);
      },
    );

    test(
      'a curated station value wins, and the override is LISTED (never silent)',
      () {
        final r = merge(
          overlay:
              '''
stations:
  - id: test-north
    name_hi: "टेस्ट उत्तर"

$_cur
''',
        );
        expect(r.snapshot.station('test-north')!.nameHi, 'टेस्ट उत्तर');
        expect(r.overrides.single.target, 'station:test-north');
        expect(r.overrides.single.field, 'name_hi');
        expect(r.overrides.single.from, isNull);
        expect(r.overrides.single.to, 'टेस्ट उत्तर');
        expect(r.overrides.single.curation.reason, 'TEST reason');
        expect(
          origin(r, 'station', 'test-north', 'name_hi')!.sourceId,
          curatedSourceId,
        );
        expect(
          origin(r, 'station', 'test-north', 'name_hi')!.status,
          OriginStatus.curatedOverride,
        );
      },
    );

    test('overriding an existing source value records the old one', () {
      final r = merge(
        overlay:
            'stations:\n  - id: test-west\n    name_en: "TEST Westward"\n$_cur',
      );
      final o = r.overrides.single;
      expect(o.from, 'TEST West');
      expect(o.to, 'TEST Westward');
      expect(r.snapshot.station('test-west')!.nameEn, 'TEST Westward');
    });

    test('curated coordinates and aliases', () {
      final r = merge(
        overlay:
            'stations:\n  - id: test-west\n    lat: 28.5\n    lng: 77.0\n    aliases: [{text: "Westy", lang: en, kind: alias}]\n$_cur',
      );
      expect(r.snapshot.station('test-west')!.lat, 28.5);
      expect(
        origin(r, 'station', 'test-west', 'lat_lng')!.sourceId,
        curatedSourceId,
      );
      expect(
        r.snapshot.namesOf('test-west').map((n) => n.text),
        contains('Westy'),
      );
    });

    test('half a coordinate is rejected', () {
      final r = merge(
        overlay: 'stations:\n  - id: test-west\n    lat: 28.5\n$_cur',
      );
      expect(conflict(r, 'overlay-bad-coordinate')!.blocking, isTrue);
    });

    test('curated overlay for an unknown station or line is an error', () {
      expect(
        conflict(
          merge(overlay: 'stations:\n  - id: nope\n    name_en: x\n$_cur'),
          'overlay-unknown-station',
        )!.blocking,
        isTrue,
      );
      expect(
        conflict(
          merge(overlay: 'lines:\n  - id: nope\n    name_en: x\n$_cur'),
          'overlay-unknown-line',
        )!.blocking,
        isTrue,
      );
    });

    test(
      'curated line overrides: Hindi name and colour (contrast text recomputed)',
      () {
        final r = merge(
          overlay:
              'lines:\n  - id: test-beta-line\n    name_hi: "बीटा"\n    color: "#FFDF00"\n$_cur',
        );
        final l = r.snapshot.line('test-beta-line')!;
        expect(l.nameHi, 'बीटा');
        expect(l.colorHex, '#FFDF00');
        expect(l.textColorHex, '#000000');
        expect(
          r.overrides.map((o) => o.field),
          containsAll(['name_hi', 'color_hex']),
        );
      },
    );

    test('curated operator id and Hindi name', () {
      final r = merge(
        overlay:
            'operators:\n  - osm_operator: "TEST Operator"\n    id: test-op\n    name_hi: "ऑपरेटर"\n$_cur',
      );
      expect(r.snapshot.operators.single.id, 'test-op');
      expect(r.snapshot.operators.single.nameHi, 'ऑपरेटर');
      expect(r.snapshot.line('test-alpha-line')!.operatorId, 'test-op');
    });

    test('release patch feeds the dataset version', () {
      expect(
        merge(overlay: 'release: {patch: 7}').snapshot.datasetVersion,
        '2026.10.7',
      );
    });
  });

  group('resolutions', () {
    final mismatch = MiniWd.bytes(
      centralEn: 'TEST Centrale',
      centralHi: 'टेस्ट केंद्र',
    );

    test(
      '"use: wikidata" applies the Wikidata value and marks the conflict resolved',
      () {
        final r = merge(
          wd: mismatch,
          overlay:
              '''
resolutions:
  - conflict: "name-en-mismatch|station:test-central|name_en"
    use: wikidata
$_cur
''',
        );
        expect(r.snapshot.station('test-central')!.nameEn, 'TEST Centrale');
        final c = conflict(r, 'name-en-mismatch')!;
        expect(c.resolved, isTrue);
        expect(c.toJson()['status'], 'resolved-by-curation');
        expect((c.toJson()['resolution']! as Map)['choice'], 'use:wikidata');
        expect(
          origin(r, 'station', 'test-central', 'name_en')!.status,
          OriginStatus.curatedOverride,
        );
      },
    );

    test('a name resolution records its source, QID and the curation text', () {
      final r = merge(
        wd: mismatch,
        overlay:
            '''
resolutions:
  - conflict: "name-en-mismatch|station:test-central|name_en"
    use: wikidata
$_cur
''',
      );
      final o = origin(r, 'station', 'test-central', 'name_en')!;
      expect(o.sourceId, wikidataSourceId);
      expect(o.externalId, startsWith('Q'));
      expect(o.status, OriginStatus.curatedOverride);
      expect(o.detail, contains('TEST reason'));
      expect(o.detail, contains('mitra-curated'));
      expect(o.detail, contains('2026-10-01'));
      expect(o.detail, contains('TEST Central'), reason: 'the replaced name');
    });

    test('"use: <literal>" picks a curated value', () {
      final r = merge(
        wd: mismatch,
        overlay:
            '''
resolutions:
  - conflict: "name-hi-mismatch|station:test-central|name_hi"
    use: "टेस्ट मध्य"
$_cur
''',
      );
      expect(r.snapshot.station('test-central')!.nameHi, 'टेस्ट मध्य');
      expect(
        origin(r, 'station', 'test-central', 'name_hi')!.sourceId,
        curatedSourceId,
      );
    });

    test('"accept" keeps the default but clears a blocking error', () {
      final r = merge(
        elements: withTags({
          103: {'wikidata': 'Q2000'},
          201: {'wikidata': 'Q2001'},
        }),
        overlay:
            '''
resolutions:
  - conflict: "multiple-wikidata|cluster:test-north@test-alpha-line"
    accept: true
$_cur
''',
      );
      expect(conflict(r, 'multiple-wikidata')!.resolved, isTrue);
      expect(r.blocking, isEmpty);
    });

    test('a resolution that matches nothing is reported as stale', () {
      final r = merge(
        overlay:
            'resolutions:\n  - conflict: "nope|x"\n    accept: true\n$_cur',
      );
      final c = conflict(r, 'resolution-unmatched')!;
      expect(c.subject, 'nope|x');
      expect(c.severity, ConflictSeverity.warning);
    });
  });

  group('determinism', () {
    test('merging twice gives identical rows in identical order', () {
      final a = merge().snapshot;
      final b = merge().snapshot;
      expect(a.stations.map((x) => x.id), b.stations.map((x) => x.id));
      expect(a.edges.map((x) => x.id), b.edges.map((x) => x.id));
      expect(a.origins.map((x) => x.key), b.origins.map((x) => x.key));
      expect(
        a.stationNames.map((x) => '${x.stationId}|${x.text}'),
        b.stationNames.map((x) => '${x.stationId}|${x.text}'),
      );
    });

    test('shuffled OSM element order gives the same dataset', () {
      final els = MiniOsm.elements();
      final a = merge(elements: els).snapshot;
      final b = merge(elements: els.reversed.toList()).snapshot;
      expect(
        a.stations.map((x) => [x.id, x.lat, x.lng, x.nameHi]),
        b.stations.map((x) => [x.id, x.lat, x.lng, x.nameHi]),
      );
      expect(
        a.edges.map((x) => [x.id, x.distanceM]),
        b.edges.map((x) => [x.id, x.distanceM]),
      );
      expect(a.services.map((x) => x.id), b.services.map((x) => x.id));
    });
  });

  group('contrastText', () {
    test('black on light colours, white on dark', () {
      expect(contrastText('#FFFFFF'), '#000000');
      expect(contrastText('#FFDF00'), '#000000');
      expect(contrastText('#000000'), '#FFFFFF');
      expect(contrastText('#C62828'), '#FFFFFF');
      expect(contrastText('#1565C0'), '#FFFFFF');
    });
  });
}
