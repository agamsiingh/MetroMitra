import 'package:data_pipeline/data_pipeline.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final snap = YamlDatasetLoader.loadFile(
    '../../data/fixtures/mini_network/dataset.yaml',
  );
  final red = {
    for (final s in snap.serviceStops)
      if (snap.services.any(
        (x) => x.id == s.serviceId && x.lineId == 'test-red',
      ))
        s.stationId,
  }.length;

  YamlMap ref(int redCount, {bool accept = false}) =>
      loadYaml('''
dmrc_total_stations: $redCount
lines:
  - { no: "1", name: "TEST Red", km: 10, stations: $redCount, line: test-red }
  - { no: "X", name: "Not in data", km: 5, stations: 3, line: no-such-line }
accepted:
${accept ? '  - { line: "X", reason: "test" }' : '  []'}
''')
          as YamlMap;

  test('matching counts pass; a line missing from the data is reported', () {
    final r = checkReference(snap, ref(red));
    expect(r.rows.first.countMatches, isTrue);
    expect(r.rows.last.datasetStations, isNull);
    expect(r.unexplained.map((x) => x.no), ['X']);
  });

  test('a documented difference is accepted, an undocumented one fails', () {
    expect(checkReference(snap, ref(red, accept: true)).unexplained, isEmpty);
    final wrong = checkReference(snap, ref(red + 1, accept: true));
    expect(wrong.unexplained.map((x) => x.no), ['1']);
  });

  test('lengths come from service distances and are compared as a ratio', () {
    final r = checkReference(snap, ref(red)).rows.first;
    expect(r.datasetKm, greaterThan(0));
    expect(r.lengthRatio, closeTo(r.datasetKm! / 10, 1e-9));
    expect(
      formatReference(checkReference(snap, ref(red))).first,
      contains('official'),
    );
  });
}
