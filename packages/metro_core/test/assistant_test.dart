@Tags(['assistant'])
library;

import 'dart:io';
import 'dart:math';

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'assistant_cases_test.dart' show fixtureAssistant;
import 'support/fixture.dart';

/// Every station / line id an answer mentions.
Iterable<String> idsIn(AssistantAnswer a) sync* {
  for (final e in a.facts.entries) {
    final v = e.value;
    if (e.key.endsWith('Id') && v is String) yield v;
    if (e.key.endsWith('Ids') && v is List) yield* v.cast<String>();
  }
  yield* a.choices;
  for (final act in a.actions) {
    switch (act) {
      case OpenRouteAction(:final fromId, :final toId):
        yield fromId;
        yield toId;
      case OpenStationAction(:final stationId):
        yield stationId;
      case OpenNearbyAction() || PickStationAction():
        break;
    }
  }
}

/// Facts that carry a metro value (as opposed to the place asked about).
const valueFacts = {
  'paise',
  'cardPaise',
  'number',
  'rows',
  'gates',
  'items',
  'lifts',
  'escalators',
  'tactile',
  'wheelchair',
  'minutes',
  'stationIds',
};

void main() {
  final snap = loadFixture();
  final a = fixtureAssistant(snap);
  final corpus = [
    for (final c
        in (loadYaml(File('test/assistant_cases.yaml').readAsStringSync())
                as YamlMap)['cases']
            as YamlList)
      (c as YamlMap)['q'] as String,
  ];

  group('no fabrication (docs/ai.md)', () {
    test('every id in every answer exists in the dataset', () {
      final known = {
        for (final s in snap.stations) s.id,
        for (final l in snap.lines) l.id,
      };
      for (final q in corpus) {
        final ans = a.ask(q);
        for (final id in idsIn(ans)) {
          expect(known, contains(id), reason: '"$q" -> $id');
        }
      }
    });

    test('"missing", "not found", "unknown" and "clarify" carry no value', () {
      for (final q in corpus) {
        final ans = a.ask(q);
        if (ans.kind == AnswerKind.answer) continue;
        // "no gate mentions <landmark>" still lists the gates the data has
        final allowed = ans.template == AnswerTemplate.gateLandmarkUnknown
            ? {'gates'}
            : const <String>{};
        for (final k in valueFacts.difference(allowed)) {
          expect(ans.facts.containsKey(k), isFalse, reason: '"$q" has $k');
        }
        expect(ans.sources, isEmpty, reason: q);
      }
    });

    test('values are the dataset values, not paraphrases', () {
      // fare = the fare engine's quote for the routed itinerary
      final fare = a.ask('fare from test alpha to test zeta');
      expect(fare.fact<int>('paise'), 5000); // the fixture's override
      final b = a.ask('fare from test beta to test delta');
      final it = RoutePlanner(snap).plan('test-beta', 'test-delta');
      expect(
        b.fact<int>('paise'),
        FareEngine(
          snap,
        ).quote(it.itineraries.first.legs).totalPaise,
      );
      // platform number from the platform row of that direction
      expect(
        a
            .ask('which platform at test gamma for test zeta')
            .fact<String>(
              'number',
            ),
        '2',
      );
      expect(
        a
            .ask('which platform at test gamma for test alpha')
            .fact<String>(
              'number',
            ),
        '1',
      );
      // timings: the fixture's minutes, untouched
      final t = a
          .ask('last metro from test alpha')
          .fact<List<Object>>('rows')
          .cast<TimingFact>();
      expect(t.single.lastDep, 1380);
      expect(t.single.terminalId, 'test-zeta');
      // gates: the fixture's gates and landmarks
      final g = a
          .ask('which gate at test alpha')
          .fact<List<Object>>('gates')
          .cast<GateInfo>();
      expect(g.map((x) => x.number), [1, 2]);
      expect(g.first.landmarksEn, ['TEST Road side']);
    });

    test('unknown (NULL) facts are left out, never turned into "no"', () {
      final acc = a.ask('lift at test alpha');
      expect(acc.facts['lifts'], 2);
      expect(acc.facts.containsKey('wheelchair'), isFalse);
      final gamma = a.ask('lift at test gamma');
      expect(gamma.facts['lifts'], 1);
      expect(gamma.facts.containsKey('escalators'), isFalse);
    });

    test('a facility the data does not list is "missing", not "none"', () {
      final r = a.ask('is there an atm at test beta');
      expect(r.kind, AnswerKind.missing);
      expect(r.template, AnswerTemplate.facilityMissing);
      expect(r.facts['facility'], FacilityType.atm);
    });

    test('parking is always "not in the data" (no parking table yet)', () {
      for (final s in snap.stations) {
        final r = a.answer(
          ParsedQuestion(intent: AssistantIntent.parking, stationId: s.id),
        );
        expect(r.kind, AnswerKind.missing);
      }
    });

    test('nonexistent places: "not found" with the user\'s own words only', () {
      for (final q in [
        'how do i reach hogwarts',
        'fare from atlantis to test zeta',
        'last metro from el dorado',
        'toilet at shangri la',
        'which platform at test gamma for narnia',
      ]) {
        final r = a.ask(q);
        expect(r.kind, AnswerKind.notFound, reason: q);
        expect(idsIn(r), isEmpty, reason: q);
      }
    });

    test('a weak fuzzy match is not taken as a place', () {
      // "zzeta" is close to nothing well enough; "tst" is too short
      for (final q in ['how to reach qqqq', 'how to reach xyzzy']) {
        expect(a.ask(q).kind, AnswerKind.notFound, reason: q);
      }
    });

    test('no data at all for the asked fact -> "missing"', () {
      final bare = snap.copyWith(
        fareSystems: const [],
        fareSlabs: const [],
        fareDiscounts: const [],
        fareOverrides: const [],
        timings: const [],
        gates: const [],
        gateLandmarks: const [],
        platforms: const [],
        facilities: const [],
        accessibility: const [],
      );
      final b = fixtureAssistant(bare);
      for (final (q, t) in [
        ('fare from test alpha to test zeta', AnswerTemplate.fareMissing),
        ('last metro from test alpha', AnswerTemplate.firstLastMissing),
        ('which gate at test alpha', AnswerTemplate.gatesMissing),
        (
          'which platform at test gamma for test iota',
          AnswerTemplate.platformMissing,
        ),
        ('toilet at test alpha', AnswerTemplate.facilityMissing),
        ('lift at test alpha', AnswerTemplate.accessibilityMissing),
      ]) {
        final r = b.ask(q);
        expect(r.kind, AnswerKind.missing, reason: q);
        expect(r.template, t, reason: q);
      }
    });

    test("a different day type uses that day's data only", () {
      final sunday = a.ask(
        'first metro from test alpha',
        context: const AssistantContext(dayType: DayType.sundayHoliday),
      );
      final rows = sunday.fact<List<Object>>('rows').cast<TimingFact>();
      expect(rows.single.firstDep, 390);
      final zetaSunday = a.ask(
        'first metro from test zeta',
        context: const AssistantContext(dayType: DayType.sundayHoliday),
      );
      expect(zetaSunday.kind, AnswerKind.missing);
    });

    test('an unreachable pair is "no route", never a made-up route', () {
      final cut = snap.copyWith(walkLinks: const []);
      final r = fixtureAssistant(cut).ask('test alpha to test mu');
      expect(r.kind, AnswerKind.missing);
      expect(r.template, AnswerTemplate.routeNone);
      expect(r.facts.containsKey('minutes'), isFalse);
    });

    test('answers carry the dataset version and fact provenance', () {
      final r = a.ask('which gate at test alpha');
      expect(r.datasetVersion, snap.datasetVersion);
      expect(r.sources, isNotEmpty);
      expect(r.sources.first.sourceId, 'test-fixture');
    });
  });

  group('clarifications', () {
    test('ambiguous place -> chips; picking one completes the question', () {
      final r = a.ask('fare from test to test zeta');
      expect(r.kind, AnswerKind.clarify);
      expect(r.template, AnswerTemplate.clarifyStation);
      expect(r.choices.length, greaterThan(1));
      expect(r.slot, AssistantSlot.from);
      final done = a.answer(r.question!.withSlot(r.slot!, 'test-beta'));
      expect(done.template, AnswerTemplate.fareFound);
      expect(done.fact<String>('fromId'), 'test-beta');
    });

    test('missing slot -> ask, then answer', () {
      final r = a.ask('which platform at test gamma');
      expect(r.template, AnswerTemplate.askDestination);
      expect(r.actions.single, isA<PickStationAction>());
      final done = a.answer(r.question!.withSlot(r.slot!, 'test-iota'));
      expect(done.template, AnswerTemplate.platformFound);
      expect(done.fact<String>('number'), '1');

      final f = a.ask('fare to test zeta');
      expect(f.template, AnswerTemplate.askFrom);
      expect(
        a.answer(f.question!.withSlot(f.slot!, 'test-alpha')).template,
        AnswerTemplate.fareFound,
      );
    });

    test('a slot filled with an id not in the dataset is "not found"', () {
      final r = a.answer(
        const ParsedQuestion(
          intent: AssistantIntent.route,
          fromId: 'test-alpha',
          toId: 'nope',
        ),
      );
      expect(r.kind, AnswerKind.notFound);
    });
  });

  group('robustness and determinism', () {
    test('same question, same answer', () {
      for (final q in corpus) {
        final x = a.ask(q);
        final y = a.ask(q);
        expect(
          '${x.kind}|${x.template}|${x.facts}|${x.choices}',
          '${y.kind}|${y.template}|${y.facts}|${y.choices}',
        );
      }
    });

    test('never throws on junk', () {
      final rnd = Random(7);
      final pool = [
        'test',
        'alpha',
        'se',
        'to',
        'from',
        'fare',
        'gate',
        '??',
        '١٢',
        'टेस्ट',
        'से',
        'platform',
        '',
        ' ',
        '\n',
        'x' * 200,
        '"',
        "'",
        'last',
        'first',
        'lift',
        'parking',
        'line',
        'zeta',
        'R1',
        '%',
      ];
      for (var i = 0; i < 500; i++) {
        final q = [
          for (var k = 0; k < rnd.nextInt(12); k++)
            pool[rnd.nextInt(pool.length)],
        ].join(' ');
        expect(() => a.ask(q), returnsNormally, reason: q);
      }
      expect(() => a.ask('test ' * 500), returnsNormally);
    });

    test('fast enough on the fixture: p50 < 20 ms per question', () {
      final times = <int>[];
      final sw = Stopwatch();
      for (final q in [...corpus, ...corpus]) {
        sw
          ..reset()
          ..start();
        a.ask(q);
        sw.stop();
        times.add(sw.elapsedMicroseconds);
      }
      times.sort();
      final p50 = times[times.length ~/ 2];
      expect(p50, lessThan(20000), reason: 'p50 ${p50}us');
    });
  });

  test('assistant sources are pure Dart: no Flutter, IO, network, plugins', () {
    for (final f in Directory(
      'lib/src/assistant',
    ).listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(
        "^import '([^']+)';",
        multiLine: true,
      ).allMatches(src)) {
        expect(
          m.group(1)!.startsWith('package:metro_core/'),
          isTrue,
          reason: '${f.path}: ${m.group(1)}',
        );
      }
      expect(src.contains('DateTime.now'), isFalse, reason: f.path);
    }
  });
}
