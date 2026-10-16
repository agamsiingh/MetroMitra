import 'dart:io';

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/search_net.dart';

void main() {
  final index = SearchIndex.fromSnapshot(searchNet());
  final doc =
      loadYaml(File('test/search_cases.yaml').readAsStringSync()) as YamlMap;
  final cases = (doc['cases'] as YamlList).cast<YamlMap>();

  test('the table has a useful number of cases', () {
    expect(cases.length, greaterThanOrEqualTo(50));
  });

  for (final c in cases) {
    final q = c['q'] as String;
    test('"$q"', () {
      final scope = switch (c['scope']) {
        'lines' => SearchScope.lines,
        'stations' => SearchScope.stations,
        _ => SearchScope.all,
      };
      final r = index.search(q, options: SearchOptions(scope: scope));
      final ids = [for (final x in r) x.entityId];
      if (c['empty'] == true) {
        expect(r, isEmpty, reason: 'got $ids');
        return;
      }
      if (c['top'] != null) {
        expect(r, isNotEmpty);
        expect(r.first.entityId, c['top'], reason: '${r.first.match}');
        if (c['tier'] != null) {
          expect(r.first.match.tier.name, c['tier']);
        }
        if (c['field'] != null) {
          expect(r.first.match.field.name, c['field']);
        }
      }
      if (c['order'] != null) {
        final order = (c['order'] as YamlList).cast<String>();
        expect(ids.take(order.length).toList(), order);
      }
      if (c['absent'] != null) {
        for (final a in (c['absent'] as YamlList).cast<String>()) {
          expect(ids, isNot(contains(a)));
        }
      }
    });
  }
}
