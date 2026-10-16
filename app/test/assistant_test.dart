import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/features/assistant/application/answer_text.dart';
import 'package:metromitra/features/assistant/application/assistant_controller.dart';
import 'package:metromitra/shared/location/location_source.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

const _fixture = '../data/fixtures/mini_network/dataset.yaml';

String _t(WidgetTester tester, String k) =>
    (tester.widget(key(k)) as Text).data ?? '';

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(key('ask-field'), q);
  await tester.tap(key('ask-send'));
  await tester.pumpAndSettle();
}

void main() {
  group('Ask tab', () {
    testWidgets('intro and suggestions; a suggestion starts the question', (
      tester,
    ) async {
      await pumpApp(tester, location: '/ask');
      expect(key('ask-intro'), findsOneWidget);
      expect(key('data-banner'), findsOneWidget);
      await tester.tap(key('suggest-route'));
      await tester.pump();
      expect(
        tester.widget<TextField>(key('ask-field')).controller!.text,
        'How do I reach ',
      );
    });

    testWidgets('a route question: answer from the data, source, open route', (
      tester,
    ) async {
      final c = await pumpApp(tester, location: '/ask');
      await _ask(tester, 'How do I reach Delta Vihar from Alpha Chowk?');
      expect(
        _t(tester, 'answer-0-headline'),
        startsWith('Alpha Chowk to Delta Vihar: About '),
      );
      expect(find.text('Lines: Test Red Line'), findsOneWidget);
      expect(_t(tester, 'answer-0-source'), startsWith('Source: metro data'));
      await tester.tap(key('act-route-0'));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/go/route');
      expect(routerOf(c).state.uri.queryParameters['from'], 'alpha');
      expect(routerOf(c).state.uri.queryParameters['to'], 'delta');
    });

    testWidgets('Hinglish and Hindi questions', (tester) async {
      await pumpApp(tester, location: '/ask');
      await _ask(tester, 'alpha chowk se central place kaise jaun');
      expect(
        _t(tester, 'answer-0-headline'),
        startsWith('Alpha Chowk to Central Place'),
      );
      await _ask(tester, 'अल्फा चौक से डेल्टा विहार कैसे जाऊं');
      expect(
        _t(tester, 'answer-1-headline'),
        startsWith('Alpha Chowk to Delta Vihar'),
      );
    });

    testWidgets('Hindi interface answers in Hindi', (tester) async {
      await pumpApp(tester, locale: const Locale('hi'), location: '/ask');
      await _ask(tester, 'अल्फा चौक से डेल्टा विहार कैसे जाऊं');
      expect(
        _t(tester, 'answer-0-headline'),
        startsWith('अल्फा चौक से डेल्टा विहार: '),
      );
    });

    testWidgets('fare: the fare engine value, nothing else', (tester) async {
      final c = await pumpApp(tester, location: '/ask');
      await _ask(tester, 'fare from alpha chowk to delta vihar');
      final services = MetroServices(demoNetwork());
      final it = services.planner.plan('alpha', 'delta').itineraries.first;
      final paise = services.fares.quote(it.legs).totalPaise!;
      expect(
        _t(tester, 'answer-0-headline'),
        contains('₹${paise ~/ 100}'),
      );
      expect(c.read(assistantProvider).single.answer.kind, AnswerKind.answer);
    });

    testWidgets('no gate data: says so, offers the station', (tester) async {
      final c = await pumpApp(tester, location: '/ask');
      await _ask(tester, 'which gate at alpha chowk');
      expect(
        _t(tester, 'answer-0-headline'),
        "I don't have verified gate information for Alpha Chowk yet.",
      );
      await tester.tap(key('act-station-0'));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/station/alpha');
    });

    testWidgets('an unknown place is "not found", never guessed', (
      tester,
    ) async {
      await pumpApp(tester, location: '/ask');
      await _ask(tester, 'how do I reach Narnia');
      expect(_t(tester, 'answer-0-headline'), contains('“narnia”'));
      expect(key('answer-0-source'), findsNothing);
    });

    testWidgets('same-named stations: chips, then the answer', (tester) async {
      final c = await pumpApp(tester, location: '/ask');
      await _ask(tester, 'twin place to alpha chowk');
      expect(
        _t(tester, 'answer-0-headline'),
        'Which station do you mean by “twin place”?',
      );
      expect(key('choice-twin-1'), findsOneWidget);
      expect(key('choice-twin-2'), findsOneWidget);
      await tester.tap(key('choice-twin-2'));
      await tester.pumpAndSettle();
      final last = c.read(assistantProvider).last;
      expect(last.chosenStationId, 'twin-2');
      expect(last.answer.template, AnswerTemplate.routeSummary);
      expect(last.answer.fact<String>('fromId'), 'twin-2');
      // older answers no longer offer the chips
      expect(key('choice-twin-1'), findsNothing);
    });

    testWidgets('after a chip, the new answer is scrolled into view '
        '(found on a device)', (tester) async {
      await pumpApp(tester, location: '/ask');
      for (var i = 0; i < 8; i++) {
        await _ask(tester, 'tell me a joke');
      }
      await _ask(tester, 'twin place to alpha chowk');
      await tester.tap(key('choice-twin-1'));
      await tester.pumpAndSettle();
      final list = tester.getRect(key('ask-list'));
      final answer = tester.getRect(key('answer-9-headline'));
      expect(answer.top, greaterThanOrEqualTo(list.top));
      expect(answer.bottom, lessThanOrEqualTo(list.bottom));
    });

    testWidgets('a missing station is chosen in the picker', (tester) async {
      final c = await pumpApp(tester, location: '/ask');
      await _ask(tester, 'how do I reach delta vihar');
      expect(_t(tester, 'answer-0-headline'), 'From which station?');
      await tester.tap(key('act-pick-0'));
      await tester.pumpAndSettle();
      await tester.enterText(key('picker-field'), 'alpha');
      await tester.pumpAndSettle();
      await tester.tap(key('station-option-alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Chosen: Alpha Chowk'), findsOneWidget);
      expect(
        c.read(assistantProvider).last.answer.template,
        AnswerTemplate.routeSummary,
      );
    });

    testWidgets('nearest metro opens Nearby (no location in the assistant)', (
      tester,
    ) async {
      final source = FakeLocationSource(
        const LocationFix(lat: 28.5, lng: 77.1),
      );
      final c = await pumpApp(
        tester,
        location: '/ask',
        locationSource: source,
      );
      await tester.tap(key('suggest-nearest'));
      await tester.pumpAndSettle();
      expect(
        _t(tester, 'answer-0-headline'),
        'See the stations closest to you.',
      );
      expect(source.calls, 0);
      await tester.tap(key('act-nearby-0'));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/go/nearby');
      expect(source.calls, 0, reason: 'Nearby asks only after its own tap');
    });

    testWidgets('anything else: what can be asked offline', (tester) async {
      await pumpApp(tester, location: '/ask');
      await _ask(tester, 'tell me a joke');
      expect(_t(tester, 'answer-0-headline'), startsWith('I can answer'));
    });

    testWidgets('very long input is capped, never a crash', (tester) async {
      final c = await pumpApp(tester, location: '/ask');
      await _ask(tester, 'alpha chowk ' * 300);
      expect(
        c.read(assistantProvider).single.question!.length,
        lessThanOrEqualTo(AssistantController.maxLength),
      );
    });
  });

  group('renderer: every template, from facts only', () {
    late MetroServices services;
    late AnswerRenderer en;
    late AnswerRenderer hi;

    setUpAll(() async {
      services = MetroServices(YamlDatasetLoader.loadFile(_fixture));
      en = AnswerRenderer(
        await AppLocalizations.delegate.load(const Locale('en')),
        services,
        const Locale('en'),
      );
      hi = AnswerRenderer(
        await AppLocalizations.delegate.load(const Locale('hi')),
        services,
        const Locale('hi'),
      );
    });

    const questions = [
      'test alpha to test zeta',
      'test alpha to test alpha',
      'nearest metro',
      'which gate at test alpha',
      'which gate for bus stop at test alpha',
      'which gate for the cinema at test alpha',
      'which gate at test gamma',
      'which platform at test gamma for test iota',
      'which platform at test alpha for test zeta',
      'fare from test alpha to test zeta',
      'last metro from test alpha',
      'last metro from test kappa',
      'test alpha to test gamma change',
      'where do i change from test alpha to test iota',
      'facilities at test alpha',
      'toilet at test alpha',
      'atm at test beta',
      'lift at test alpha',
      'lift at test beta',
      'parking at test alpha',
      'test red line stations',
      'how do i reach narnia',
      'test',
      'fare to test zeta',
      'which platform at test gamma',
      'toilet',
      'tell me a joke',
    ];

    test('all templates are reachable and render in English and Hindi', () {
      final seen = <AnswerTemplate>{};
      for (final q in questions) {
        final a = services.assistant.ask(q);
        seen.add(a.template);
        for (final r in [en, hi]) {
          final t = r.render(a);
          expect(t.headline, isNotEmpty, reason: q);
          expect(t.headline.contains('test-'), isFalse, reason: 'raw id: $q');
          r.source(a);
        }
      }
      // routeNone / fareMissing / askTo need other data: rendered directly
      for (final a in [
        const AssistantAnswer(
          intent: AssistantIntent.route,
          kind: AnswerKind.missing,
          template: AnswerTemplate.routeNone,
          datasetVersion: 'v',
          facts: {'fromId': 'test-alpha', 'toId': 'test-mu'},
        ),
        const AssistantAnswer(
          intent: AssistantIntent.fare,
          kind: AnswerKind.missing,
          template: AnswerTemplate.fareMissing,
          datasetVersion: 'v',
          facts: {'fromId': 'test-alpha', 'toId': 'test-mu'},
        ),
        const AssistantAnswer(
          intent: AssistantIntent.route,
          kind: AnswerKind.clarify,
          template: AnswerTemplate.askTo,
          datasetVersion: 'v',
        ),
      ]) {
        seen.add(a.template);
        expect(en.render(a).headline, isNotEmpty);
        expect(hi.render(a).headline, isNotEmpty);
      }
      expect(seen, containsAll(AnswerTemplate.values));
    });

    test('labels inside an English sentence: lower-case, acronyms kept', () {
      final toilet = services.assistant.ask('toilet at test gamma');
      expect(en.render(toilet).headline, contains('no record of toilet at'));
      final atm = services.assistant.ask('atm at test beta');
      expect(en.render(atm).headline, contains('no record of ATM at'));
    });

    test('times past midnight are labelled; 24-hour clock', () {
      expect(en.clock(360), '06:00');
      expect(en.clock(1380), '23:00');
      expect(en.clock(1470), '00:30 (after midnight)');
    });

    test('source shows the weakest confidence and its check date', () {
      final a = services.assistant.ask('fare from test alpha to test zeta');
      expect(en.source(a), startsWith('Source: metro data 2'));
      final g = services.assistant.ask('which gate at test alpha');
      expect(en.source(g), contains('community-sourced'));
    });
  });
}
