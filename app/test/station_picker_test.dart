import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/go/application/station_options.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

Future<void> openPicker(
  WidgetTester tester, {
  JourneyEnd end = JourneyEnd.from,
}) async {
  await tester.tap(key('field-${end.name}'));
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String q) async {
  await tester.enterText(key('picker-field'), q);
  await tester.pumpAndSettle();
}

void main() {
  group('station options (application layer, no widgets)', () {
    final services = MetroServices(demoNetwork());

    test('blank query is blank, not an error', () {
      expect(searchStationOptions(services, '').isBlank, isTrue);
      expect(searchStationOptions(services, '   ').isBlank, isTrue);
      expect(searchStationOptions(services, '   ').isEmpty, isTrue);
    });

    test('English, Hindi, alias and code all resolve to the canonical id', () {
      for (final q in ['central place', 'सेंट्रल प्लेस', 'old central', 'CP']) {
        final r = searchStationOptions(services, q);
        expect(r.direct.first.id, 'central', reason: q);
      }
    });

    test('rows carry names, lines with data colours, interchange flag', () {
      final o = searchStationOptions(services, 'central place').direct.first;
      expect(o.nameEn, 'Central Place');
      expect(o.nameHi, 'सेंट्रल प्लेस');
      expect(o.isInterchange, isTrue);
      expect(o.lines.map((l) => l.lineId), ['red', 'blue']);
      expect(o.lines.first.colorHex, '#C62828');
      expect(o.lines.first.code, 'CP');
      expect(o.matchedText, isNull, reason: 'matched on its own name');
    });

    test('an alias or code match says why the row is listed', () {
      expect(
        searchStationOptions(services, 'old central').direct.first.matchedText,
        'Old Central',
      );
      expect(
        searchStationOptions(services, 'CP').direct.first.matchedText,
        'CP',
      );
    });

    test('missing Hindi name stays null', () {
      final o = searchStationOptions(services, 'xray gate').direct.first;
      expect(o.nameHi, isNull);
    });

    test('closed stations are not offered', () {
      expect(searchStationOptions(services, 'halt road').isEmpty, isTrue);
    });

    test('similar names are separated from direct matches', () {
      final r = searchStationOptions(services, 'alpah chowk');
      expect(r.direct, isEmpty);
      expect(r.similar.first.id, 'alpha');
      expect(r.similar.first.isSimilar, isTrue);
    });

    test('stationOptionFor resolves by id, null for unknown ids', () {
      expect(stationOptionFor(services, 'beta')!.nameEn, 'Beta Nagar');
      expect(stationOptionFor(services, 'Beta Nagar'), isNull);
      expect(stationOptionFor(services, 'nope'), isNull);
    });

    test('is deterministic', () {
      final a = searchStationOptions(services, 'place').direct.map((o) => o.id);
      final b = searchStationOptions(services, 'place').direct.map((o) => o.id);
      expect(a.toList(), b.toList());
    });
  });

  group('picker screen', () {
    testWidgets('opens full screen with a hint and no results yet', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      expect(key('picker-field'), findsOneWidget);
      expect(key('picker-blank'), findsOneWidget);
      expect(find.text('Choose starting station'), findsOneWidget);
      expect(find.text('Search for a station'), findsOneWidget);
      // full screen: the bottom navigation is not shown
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('To picker has its own title', (tester) async {
      await pumpApp(tester);
      await openPicker(tester, end: JourneyEnd.to);
      expect(find.text('Choose destination'), findsOneWidget);
    });

    testWidgets('typing an English name lists the station with its details', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      await type(tester, 'central');
      expect(key('station-option-central'), findsOneWidget);
      expect(find.text('Central Place'), findsOneWidget);
      expect(find.text('सेंट्रल प्लेस'), findsOneWidget);
      expect(key('interchange-central'), findsOneWidget);
      expect(find.text('Interchange'), findsOneWidget);
      expect(find.textContaining('Test Red Line · CP'), findsWidgets);
      expect(find.textContaining('Test Blue Line · CP'), findsWidgets);
    });

    testWidgets('Hindi names, aliases and codes are searchable', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      await type(tester, 'बीटा');
      expect(key('station-option-beta'), findsOneWidget);
      await type(tester, 'old central');
      expect(key('station-option-central'), findsOneWidget);
      expect(find.text('Also known as: Old Central'), findsOneWidget);
      await type(tester, 'bt');
      expect(key('station-option-beta'), findsOneWidget);
    });

    testWidgets('a station without a Hindi name shows only its English name', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      await type(tester, 'xray');
      expect(key('station-option-xray'), findsOneWidget);
      expect(find.text('Xray Gate'), findsOneWidget);
      // nothing invented: no placeholder, no transliteration
      expect(find.text('-'), findsNothing);
      expect(find.text('—'), findsNothing);
      final tile = tester.widget<InkWell>(key('station-option-xray'));
      expect(tile, isNotNull);
      final texts = find
          .descendant(
            of: key('station-option-xray'),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .toList();
      expect(
        texts.any((t) => t != null && RegExp('[ऀ-ॿ]').hasMatch(t)),
        isFalse,
      );
    });

    testWidgets('no results shows a clear message with the query', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      await type(tester, 'qqqqqqq');
      expect(key('picker-no-results'), findsOneWidget);
      expect(find.text('No station called “qqqqqqq”'), findsOneWidget);
      expect(key('picker-results'), findsNothing);
    });

    testWidgets('clearing the field returns to the blank state', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      await type(tester, 'beta');
      expect(key('station-option-beta'), findsOneWidget);
      await tester.tap(key('picker-clear'));
      await tester.pumpAndSettle();
      expect(key('picker-blank'), findsOneWidget);
    });

    testWidgets('a typo offers "Did you mean"', (tester) async {
      await pumpApp(tester);
      await openPicker(tester);
      await type(tester, 'alpah chowk');
      expect(key('picker-similar-header'), findsOneWidget);
      expect(find.text('Did you mean'), findsOneWidget);
      expect(key('station-option-alpha'), findsOneWidget);
    });

    testWidgets('direct matches come before similar ones, with a header', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      await type(tester, 'ring');
      expect(key('station-option-ringa'), findsOneWidget);
      expect(find.text('Similar names'), findsNothing);
    });

    testWidgets('two stations with the same name stay distinguishable', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      await type(tester, 'twin place');
      expect(key('station-option-twin-1'), findsOneWidget);
      expect(key('station-option-twin-2'), findsOneWidget);
      // told apart by their lines
      expect(
        find.descendant(
          of: key('station-option-twin-1'),
          matching: find.textContaining('Test Red Line'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('station-option-twin-2'),
          matching: find.textContaining('Test Blue Line'),
        ),
        findsOneWidget,
      );
    });
  });

  group('selection resolves to the canonical station id', () {
    testWidgets('picking From stores the id and shows the station on Home', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      await pickStation(tester, JourneyEnd.from, 'beta', 'beta');
      expect(selection(c).fromId, 'beta');
      expect(selection(c).toId, isNull);
      expect(find.text('Beta Nagar'), findsOneWidget);
      expect(find.text('बीटा नगर'), findsOneWidget);
    });

    testWidgets('same-named stations are told apart by id, not by name', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      await pickStation(tester, JourneyEnd.to, 'twin place', 'twin-2');
      expect(selection(c).toId, 'twin-2');
      await pickStation(tester, JourneyEnd.from, 'twin place', 'twin-1');
      expect(selection(c).fromId, 'twin-1');
      expect(selection(c).fromId, isNot(selection(c).toId));
      expect(selection(c).isSameStation, isFalse);
    });

    testWidgets('picking by alias or code still stores the real id', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      await pickStation(tester, JourneyEnd.from, 'old central', 'central');
      expect(selection(c).fromId, 'central');
      await pickStation(tester, JourneyEnd.to, 'AL1', 'alpha');
      expect(selection(c).toId, 'alpha');
    });

    testWidgets('going back without choosing changes nothing', (tester) async {
      final c = await pumpApp(tester);
      await pickStation(tester, JourneyEnd.from, 'beta', 'beta');
      await openPicker(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(selection(c).fromId, 'beta');
    });
  });

  group('Hindi interface', () {
    testWidgets('Hindi name is primary, English the subtitle', (tester) async {
      await pumpApp(tester, locale: const Locale('hi'));
      await openPicker(tester);
      await type(tester, 'beta');
      final tile = key('station-option-beta');
      expect(
        find.descendant(of: tile, matching: find.text('बीटा नगर')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('Beta Nagar')),
        findsOneWidget,
      );
    });

    testWidgets('a station with no Hindi name falls back to English only', (
      tester,
    ) async {
      await pumpApp(tester, locale: const Locale('hi'));
      await openPicker(tester);
      await type(tester, 'xray');
      expect(
        find.descendant(
          of: key('station-option-xray'),
          matching: find.text('Xray Gate'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('empty state strings are translated', (tester) async {
      await pumpApp(tester, locale: const Locale('hi'));
      await openPicker(tester);
      expect(find.text('स्टेशन खोजें'), findsOneWidget);
    });
  });
}
