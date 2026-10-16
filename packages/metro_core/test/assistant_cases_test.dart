@Tags(['assistant'])
library;

import 'dart:io';

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/fixture.dart';

OfflineAssistant fixtureAssistant([MetroSnapshot? snapshot]) {
  final s = snapshot ?? loadFixture();
  final fares = FareEngine(s);
  return OfflineAssistant(
    snapshot: s,
    search: SearchIndex.fromSnapshot(s),
    planner: RoutePlanner(s, fareEngine: fares),
    fares: fares,
  );
}

void main() {
  final assistant = fixtureAssistant();
  final doc =
      loadYaml(File('test/assistant_cases.yaml').readAsStringSync()) as YamlMap;
  final cases = (doc['cases'] as YamlList).cast<YamlMap>();

  test('corpus: at least 150 utterances in English, Hindi and Hinglish', () {
    expect(cases.length, greaterThanOrEqualTo(150));
    final langs = <String, int>{};
    for (final c in cases) {
      langs[c['lang'] as String] = (langs[c['lang']] ?? 0) + 1;
    }
    for (final l in ['en', 'hi', 'hinglish']) {
      expect(langs[l], greaterThanOrEqualTo(30), reason: l);
    }
    // every intent of docs/ai.md is covered
    final intents = {for (final c in cases) c['intent']};
    for (final i in AssistantIntent.values) {
      expect(intents, contains(i.name));
    }
  });

  for (final c in cases) {
    final q = c['q'] as String;
    test('${c['lang']}: "$q"', () {
      final p = assistant.understand(q);
      expect(p.intent.name, c['intent'], reason: '$p');
      final slots = {
        'from': p.fromId,
        'to': p.toId,
        'station': p.stationId,
        'dest': p.destinationId,
        'line': p.lineId,
        'facility': p.facility?.name,
      };
      for (final e in slots.entries) {
        if (c.containsKey(e.key)) {
          expect(e.value, c[e.key], reason: '${e.key} in $p');
        }
      }
      final a = assistant.ask(q);
      expect(a.kind.name, c['kind'], reason: '${a.template} ${a.facts}');
      expect(a.template.name, c['template'], reason: '${a.facts}');
    });
  }
}
