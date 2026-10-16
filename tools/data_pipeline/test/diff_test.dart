import 'dart:io';

import 'package:data_pipeline/data_pipeline.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:test/test.dart';

import 'support/support.dart';

void main() {
  late Directory tmp;
  late MetroSnapshot base;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('diff_test_');
    final ws = Workspace.create();
    base = buildDataset(ws.paths).snapshot!;
    ws.dispose();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(MetroSnapshot s, String name) {
    DatasetWriter.writeFile(s, '${tmp.path}/$name.sqlite');
    return '${tmp.path}/$name.sqlite';
  }

  DatasetDiff diff(MetroSnapshot changed) =>
      diffFiles(write(base, 'a'), write(changed, 'b'));

  List<T> replace<T>(List<T> l, bool Function(T) test, T Function(T) f) => [
    for (final x in l) test(x) ? f(x) : x,
  ];

  test('identical datasets: empty diff', () {
    final d = diff(base);
    expect(d.isEmpty, isTrue);
    expect(d.toText(), 'No differences.');
    expect(d.toJson()['empty'], isTrue);
  });

  test('added and removed stations', () {
    final a = memoryDb(base);
    final b = memoryDb(base)
      ..execute("DELETE FROM origin WHERE entity_id = 'test-west'")
      ..execute("DELETE FROM station_name WHERE station_id = 'test-west'")
      ..execute("DELETE FROM station WHERE id = 'test-west'")
      ..execute(
        'INSERT INTO station (id, name_en, lat, lng, popularity, status, '
        "source_id, confidence) VALUES ('test-new', 'TEST New', 28.6, 77.1, "
        "0, 'open', 'osm-overpass', 'community')",
      );
    final d = diffDatabases(a, b);
    a.close();
    b.close();
    expect(d.stationsAdded, ['test-new']);
    expect(d.stationsRemoved, ['test-west']);
    expect(
      d.toText(),
      allOf(contains('Stations added (1)'), contains('Stations removed (1)')),
    );
  });

  test('renamed stations (English and Hindi)', () {
    final changed = base.copyWith(
      stations: replace(
        base.stations,
        (s) => s.id == 'test-central',
        (s) => Station(
          id: s.id,
          nameEn: 'TEST Central Renamed',
          nameHi: 'नया नाम',
          lat: s.lat,
          lng: s.lng,
          status: s.status,
          provenance: s.provenance,
        ),
      ),
    );
    final d = diff(changed);
    final r = d.stationsRenamed['test-central']!;
    expect(r['name_en'], ['TEST Central', 'TEST Central Renamed']);
    expect(r['name_hi']![1], 'नया नाम');
    expect(d.toText(), contains('Stations renamed'));
    expect(d.coordinateMoves, isEmpty);
  });

  test('changed coordinates report the distance moved', () {
    final changed = base.copyWith(
      stations: replace(
        base.stations,
        (s) => s.id == 'test-north',
        (s) => Station(
          id: s.id,
          nameEn: s.nameEn,
          nameHi: s.nameHi,
          lat: s.lat + 0.001,
          lng: s.lng,
          status: s.status,
          provenance: s.provenance,
        ),
      ),
    );
    final d = diff(changed);
    expect(d.coordinateMoves.keys, ['test-north']);
    expect(d.coordinateMoves['test-north'], inInclusiveRange(105, 117));
    expect(d.stationsRenamed, isEmpty);
    expect(d.toText(), contains('Coordinates changed'));
  });

  test('changed lines: colour, name, removed line', () {
    final a = memoryDb(base);
    final b = memoryDb(base)
      ..execute("DELETE FROM line WHERE id = 'test-beta-line'")
      ..execute(
        "UPDATE line SET name_en = 'TEST Alpha Line 2', color_hex = '#00FF00' "
        "WHERE id = 'test-alpha-line'",
      );
    final d = diffDatabases(a, b);
    a.close();
    b.close();
    final lines = d.lineChanges['line']!;
    expect(lines.removed, ['test-beta-line']);
    expect(
      lines.changed['test-alpha-line']!.keys,
      containsAll(['name_en', 'color_hex']),
    );
    expect(d.toText(), contains('Changed line'));
  });

  test(
    'changed relationships: line membership, stop order, edges, transfers',
    () {
      final a = memoryDb(base);
      final b = memoryDb(base)
        ..execute("DELETE FROM station_line WHERE station_id = 'test-north'")
        ..execute('DELETE FROM transfer')
        ..execute(
          "DELETE FROM edge WHERE from_station = 'test-north' OR to_station = 'test-north'",
        )
        ..execute(
          "UPDATE service_stop SET seq = seq + 10 WHERE station_id = 'test-north'",
        );
      final d = diffDatabases(a, b);
      a.close();
      b.close();
      final rel = d.relationshipChanges;
      expect(rel['station_line']!.removed, ['test-north|test-alpha-line']);
      expect(rel['transfer']!.removed, hasLength(2));
      expect(rel['edge']!.removed, hasLength(2));
      expect(rel['service_stop'], isNotNull);
      expect(d.curatedFactChanges, isEmpty);
    },
  );

  test('changed curated facts are listed separately', () {
    final withFacts = base.copyWith(
      gates: [
        Gate(
          id: 'test-central:g1',
          stationId: 'test-central',
          number: 1,
          provenance: base.stations.first.provenance,
        ),
      ],
    );
    final d = diff(withFacts);
    expect(d.curatedFactChanges.keys, ['gate']);
    expect(d.curatedFactChanges['gate']!.added, ['test-central:g1']);
    expect(d.relationshipChanges, isEmpty);
    expect(d.toText(), contains('Changed curated facts: gate'));
  });

  test('changed provenance (origin) and meta are visible', () {
    final changed = base.copyWith(
      meta: {...base.meta, 'dataset_version': '2026.11.0'},
      origins: base.origins.skip(1).toList(),
    );
    final d = diff(changed);
    expect(d.originChanges.removed, hasLength(1));
    expect(
      d.toText(),
      allOf(
        contains('Changed meta'),
        contains('2026.11.0'),
        contains('origin'),
      ),
    );
  });

  test('JSON output has the headline lists', () {
    final changed = base.copyWith(
      stations: replace(
        base.stations,
        (s) => s.id == 'test-west',
        (s) => Station(
          id: s.id,
          nameEn: 'TEST Westx',
          nameHi: s.nameHi,
          lat: s.lat,
          lng: s.lng,
          status: s.status,
          provenance: s.provenance,
        ),
      ),
    );
    final j = diff(changed).toJson();
    expect(j['empty'], isFalse);
    expect((j['stations_renamed']! as Map).keys, ['test-west']);
    expect(j['tables'], contains('station'));
  });

  test('the text report truncates long lists but keeps the count', () {
    final many = base.copyWith(
      stationNames: [
        ...base.stationNames,
        for (var i = 0; i < 30; i++)
          StationName(
            stationId: 'test-west',
            text: 'alias $i',
            lang: 'en',
            kind: NameKind.alias,
          ),
      ],
    );
    final d = diff(many);
    expect(d.tables['station_name']!.added, hasLength(30));
  });

  test('diff of a dataset with an unreadable file fails clearly', () {
    File('${tmp.path}/junk.sqlite').writeAsStringSync('nope' * 100);
    expect(
      () => diffFiles(write(base, 'ok'), '${tmp.path}/junk.sqlite'),
      throwsA(anything),
    );
  });
}
