import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/features/assistant/application/ai_providers.dart';

import 'support/app_harness.dart';

class FakeGateway implements AiGateway {
  FakeGateway(this.result);

  AiResult result;
  final requests = <AiRequest>[];
  Completer<void>? hold;

  @override
  bool get configured => true;

  @override
  Future<AiResult> ask(AiRequest request) async {
    requests.add(request);
    await hold?.future;
    return result;
  }
}

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(key('ask-field'), q);
  await tester.tap(key('ask-send'));
  await tester.pumpAndSettle();
}

String _t(WidgetTester tester, String k) =>
    (tester.widget(key(k)) as Text).data ?? '';

void main() {
  group('Ask tab with the optional online AI', () {
    testWidgets('an unknown question: offline answer first, then the AI card, '
        'labelled', (tester) async {
      final gw = FakeGateway(const AiAnswer('Keep your card ready.'))
        ..hold = Completer<void>();
      await pumpApp(
        tester,
        location: '/ask',
        extraOverrides: [aiGatewayProvider.overrideWithValue(gw)],
      );
      await tester.enterText(key('ask-field'), 'tell me a joke');
      await tester.tap(key('ask-send'));
      await tester.pump();
      await tester.pump();
      expect(_t(tester, 'answer-0-headline'), startsWith('I can answer'));
      expect(key('ai-0'), findsOneWidget);
      expect(find.text('Asking the AI…'), findsOneWidget);
      gw.hold!.complete();
      await tester.pumpAndSettle();
      expect(_t(tester, 'ai-0-text'), 'Keep your card ready.');
      expect(_t(tester, 'ai-0-label'), startsWith('AI-generated'));
      expect(find.textContaining('No location'), findsOneWidget);
      // the offline answer is still there, unchanged
      expect(_t(tester, 'answer-0-headline'), startsWith('I can answer'));
    });

    testWidgets('known questions never go to the AI', (tester) async {
      final gw = FakeGateway(const AiAnswer('x'));
      await pumpApp(
        tester,
        location: '/ask',
        extraOverrides: [aiGatewayProvider.overrideWithValue(gw)],
      );
      await _ask(tester, 'fare from alpha chowk to delta vihar');
      await _ask(tester, 'which gate at alpha chowk');
      await _ask(tester, 'how do I reach Narnia');
      expect(gw.requests, isEmpty);
      expect(key('ai-0'), findsNothing);
    });

    testWidgets('the request carries only the question, locale and dataset '
        'facts', (tester) async {
      final gw = FakeGateway(const AiAnswer('ok'));
      await pumpApp(
        tester,
        location: '/ask',
        extraOverrides: [aiGatewayProvider.overrideWithValue(gw)],
      );
      await _ask(tester, 'tell me a joke');
      final r = gw.requests.single;
      expect(r.question, 'tell me a joke');
      expect(r.locale, 'en');
      expect(
        r.grounding.every((f) => f.key == 'station' || f.key == 'line'),
        isTrue,
      );
    });

    testWidgets('offline: the exact wording, and the offline answer stays', (
      tester,
    ) async {
      final gw = FakeGateway(const AiUnavailable('no network'));
      await pumpApp(
        tester,
        location: '/ask',
        extraOverrides: [aiGatewayProvider.overrideWithValue(gw)],
      );
      await _ask(tester, 'tell me a joke');
      expect(_t(tester, 'ai-0-text'), 'Connect to internet for an AI answer.');
      expect(_t(tester, 'answer-0-headline'), startsWith('I can answer'));
    });

    testWidgets('rate limit and refused answers get plain messages', (
      tester,
    ) async {
      final gw = FakeGateway(const AiUnavailable('rate limited'));
      await pumpApp(
        tester,
        location: '/ask',
        extraOverrides: [aiGatewayProvider.overrideWithValue(gw)],
      );
      await _ask(tester, 'tell me a joke');
      expect(_t(tester, 'ai-0-text'), contains('not available right now'));
      gw.result = const AiRefused('failed the on-device check');
      await _ask(tester, 'tell me another joke');
      expect(_t(tester, 'ai-1-text'), "Couldn't verify this answer.");
    });

    testWidgets('the user can switch online AI off', (tester) async {
      final gw = FakeGateway(const AiAnswer('x'));
      final c = await pumpApp(
        tester,
        location: '/ask',
        extraOverrides: [aiGatewayProvider.overrideWithValue(gw)],
      );
      c.read(onlineAiEnabledProvider.notifier).set(enabled: false);
      await _ask(tester, 'tell me a joke');
      expect(gw.requests, isEmpty);
      expect(key('ai-0'), findsNothing);
    });

    testWidgets('no gateway configured: nothing AI is shown', (tester) async {
      await pumpApp(tester, location: '/ask');
      await _ask(tester, 'tell me a joke');
      expect(key('ai-0'), findsNothing);
      expect(find.textContaining('Connect to internet'), findsNothing);
    });

    testWidgets('Hindi interface asks for a Hindi answer', (tester) async {
      final gw = FakeGateway(const AiAnswer('ठीक है'));
      await pumpApp(
        tester,
        locale: const Locale('hi'),
        location: '/ask',
        extraOverrides: [aiGatewayProvider.overrideWithValue(gw)],
      );
      await _ask(tester, 'tell me a joke');
      expect(gw.requests.single.locale, 'hi');
    });
  });
}
