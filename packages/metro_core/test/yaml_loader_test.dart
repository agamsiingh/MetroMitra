import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  group('fixture is clearly marked test data', () {
    final s = loadFixture();

    test('meta flags it and every source says TEST DATA', () {
      expect(s.isTestData, isTrue);
      expect(s.meta[MetaKeys.attribution], contains('TEST DATA'));
      expect(s.sources.single.name, contains('TEST DATA'));
      expect(s.sources.single.id, 'test-fixture');
    });

    test('every station and line name carries the TEST marker', () {
      for (final st in s.stations) {
        expect(st.nameEn, startsWith('TEST'), reason: st.id);
        expect(st.id, startsWith('test-'));
      }
      for (final l in s.lines) {
        expect(l.nameEn, startsWith('TEST'), reason: l.id);
      }
    });

    test('no fact claims to be verified or official', () {
      final all = <Provenance>[
        ...s.stations.map((x) => x.provenance),
        ...s.edges.map((x) => x.provenance),
        ...s.gates.map((x) => x.provenance),
        ...s.platforms.map((x) => x.provenance),
        ...s.facilities.map((x) => x.provenance),
        ...s.accessibility.map((x) => x.provenance),
        ...s.timings.map((x) => x.provenance),
      ];
      expect(all.where((p) => p.confidence.requiresVerifiedOn), isEmpty);
    });
  });

  group('loading the fixture', () {
    final s = loadFixture();

    test('covers every table required by M1', () {
      expect(s.stations, hasLength(12));
      expect(s.lines, hasLength(3));
      expect(s.operators, hasLength(2));
      expect(s.services, hasLength(3));
      expect(s.stationLines, isNotEmpty);
      expect(s.edges, isNotEmpty);
      expect(s.stationNames.where((n) => n.kind == NameKind.alias), isNotEmpty);
      expect(s.platforms, isNotEmpty);
      expect(s.gates, isNotEmpty);
      expect(s.gateLandmarks, isNotEmpty);
      expect(s.facilities, isNotEmpty);
      expect(s.accessibility, isNotEmpty);
      expect(s.fareSystems, hasLength(2));
      expect(s.fareSlabs, isNotEmpty);
      expect(s.fareDiscounts, isNotEmpty);
      expect(s.fareOverrides, isNotEmpty);
      expect(s.timings, isNotEmpty);
      expect(s.transfers, isNotEmpty);
      expect(s.walkLinks, hasLength(1));
    });

    test('derives both directed edges per consecutive stop pair', () {
      // red 5 pairs + blue 3 + green 2 = 10 pairs -> 20 directed edges
      expect(s.edges, hasLength(20));
      final ab = s.edges.firstWhere(
        (e) => e.fromStation == 'test-alpha' && e.toStation == 'test-beta',
      );
      final ba = s.edges.firstWhere(
        (e) => e.fromStation == 'test-beta' && e.toStation == 'test-alpha',
      );
      expect(ab.travelS, ba.travelS);
      expect(ab.distanceM, 1200);
      expect(ab.provenance.confidence, Confidence.derived);
    });

    test('derives station_line, incl. interchange on two lines', () {
      expect(
        s.linesAt('test-gamma').map((l) => l.id),
        unorderedEquals(['test-red', 'test-blue']),
      );
      expect(s.linesAt('test-alpha').map((l) => l.id), ['test-red']);
      final code = s.stationLines.firstWhere(
        (x) => x.stationId == 'test-gamma' && x.lineId == 'test-blue',
      );
      expect(code.stationCode, 'B2');
    });

    test('gate ids are <station>:g<number>; unknown booleans stay null', () {
      final g2 = s.gates.firstWhere((g) => g.id == 'test-alpha:g2');
      expect(g2.hasLift, isNull);
      expect(g2.isStepFree, isNull);
      final g1 = s.gates.firstWhere((g) => g.id == 'test-alpha:g1');
      expect(g1.hasLift, isTrue);
      expect(s.landmarksOf('test-alpha:g1').single.kind, GateLandmarkKind.road);
    });

    test('missing data is absent, not defaulted', () {
      expect(s.gatesAt('test-gamma'), isEmpty);
      expect(s.accessibilityAt('test-beta'), isNull);
      expect(s.accessibilityAt('test-alpha')!.wheelchairAvailable, isNull);
      expect(s.accessibilityAt('test-gamma')!.escalators, isNull);
    });

    test('post-midnight times are kept as minutes beyond 1440', () {
      final blue = s.timings.firstWhere((t) => t.serviceId == 'test-blue-main');
      expect(blue.lastDep, 1470);
    });

    test('official names become station_name rows in en and hi', () {
      final names = s.namesOf('test-alpha');
      expect(
        names.where((n) => n.kind == NameKind.official).map((n) => n.lang),
        unorderedEquals(['en', 'hi']),
      );
      expect(
        names.any((n) => n.kind == NameKind.misspelling),
        isTrue,
      );
    });

    test('snapshot lookups', () {
      expect(s.station('test-alpha')!.nameEn, 'TEST Alpha');
      expect(s.station('nope'), isNull);
      expect(s.stopsOf('test-red-main').map((x) => x.stationId), [
        'test-alpha',
        'test-beta',
        'test-gamma',
        'test-delta',
        'test-epsilon',
        'test-zeta',
      ]);
      expect(s.servicesOfLine('test-blue').single.id, 'test-blue-main');
      expect(s.transfersAt('test-gamma'), hasLength(2));
      expect(s.walkLinksOf('test-kappa').single.requiresExit, isTrue);
      expect(s.fareSystemOf('test-op-b')!.id, 'test-fare-b');
      expect(s.edgesFrom('test-gamma'), hasLength(4));
    });
  });

  group('strict authoring parse', () {
    String minimal({String extra = ''}) =>
        '''
meta: {dataset_version: "2026.10.0", built_at: x, city: c, attribution: a, bbox: "0,0,1,1"}
$extra
''';

    test('empty document parses to an empty snapshot', () {
      final s = YamlDatasetLoader.parse(minimal());
      expect(s.stations, isEmpty);
      expect(s.schemaVersion, currentSchemaVersion);
    });

    test('unknown top-level key is rejected', () {
      expect(
        () => YamlDatasetLoader.parse(minimal(extra: 'statoins: []')),
        throwsA(
          isA<AuthoringException>().having(
            (e) => e.message,
            'message',
            contains('statoins'),
          ),
        ),
      );
    });

    test('unknown nested key is rejected with its path', () {
      const yaml = '''
meta: {}
sources:
  - {id: a, name: n, license: l, typo_key: 1}
''';
      expect(
        () => YamlDatasetLoader.parse(yaml),
        throwsA(
          isA<AuthoringException>().having(
            (e) => e.message,
            'message',
            allOf(contains('sources[0]'), contains('typo_key')),
          ),
        ),
      );
    });

    test('missing required field names the node', () {
      const yaml = '''
meta: {}
sources:
  - {id: a, license: l}
''';
      expect(
        () => YamlDatasetLoader.parse(yaml),
        throwsA(
          isA<AuthoringException>().having(
            (e) => e.message,
            'message',
            contains('missing "name"'),
          ),
        ),
      );
    });

    test('wrong type is rejected', () {
      const yaml = '''
meta: {}
lines:
  - {id: l, operator: o, name_en: a, name_hi: b, color: "#000000", text_color: "#FFFFFF", sort: high, status: open}
''';
      expect(
        () => YamlDatasetLoader.parse(yaml),
        throwsA(isA<AuthoringException>()),
      );
    });

    test('unknown enum value is rejected', () {
      const yaml = '''
meta: {}
lines:
  - {id: l, operator: o, name_en: a, name_hi: b, color: "#000000", text_color: "#FFFFFF", sort: 1, status: sideways}
''';
      expect(
        () => YamlDatasetLoader.parse(yaml),
        throwsA(isA<FormatException>()),
      );
    });

    test('next_travel_s without edge_provenance is rejected', () {
      const yaml = '''
meta: {}
lines:
  - id: l
    operator: o
    name_en: a
    name_hi: b
    color: "#000000"
    text_color: "#FFFFFF"
    sort: 1
    status: open
    services:
      - id: s
        name: n
        stops:
          - {station: a, dist_m: 0, next_travel_s: 60}
          - {station: b, dist_m: 100}
''';
      expect(
        () => YamlDatasetLoader.parse(yaml),
        throwsA(
          isA<AuthoringException>().having(
            (e) => e.message,
            'message',
            contains('edge_provenance'),
          ),
        ),
      );
    });

    test('top level must be a map', () {
      expect(
        () => YamlDatasetLoader.parse('- a\n- b'),
        throwsA(isA<AuthoringException>()),
      );
    });
  });
}
