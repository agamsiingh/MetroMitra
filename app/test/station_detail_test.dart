import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' as core show Platform;
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/features/go/application/journey_provider.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

String _t(WidgetTester tester, String k) =>
    (tester.widget(key(k)) as Text).data ?? '';

void main() {
  group('opens by canonical id only', () {
    testWidgets('a station id resolves; names, codes and junk do not', (
      tester,
    ) async {
      final c = await pumpApp(tester, location: '/station/central');
      expect(_t(tester, 'station-name'), 'Central Place');

      for (final bad in ['Central%20Place', 'CP', 'nope']) {
        routerOf(c).go('/station/$bad');
        await tester.pumpAndSettle();
        expect(key('station-not-found'), findsOneWidget, reason: bad);
      }
    });

    testWidgets('same-named stations are told apart by id and lines', (
      tester,
    ) async {
      final c = await pumpApp(tester, location: '/station/twin-1');
      expect(find.text('Test Red Line · TW'), findsOneWidget);
      routerOf(c).go('/station/twin-2');
      await tester.pumpAndSettle();
      expect(find.text('Test Blue Line · TW'), findsOneWidget);
      expect(find.text('Test Red Line · TW'), findsNothing);
    });
  });

  group('what is shown', () {
    testWidgets('interchange: names, lines with codes, aliases, services, '
        'status, coordinates, source', (tester) async {
      await pumpApp(tester, location: '/station/central');
      expect(_t(tester, 'station-name'), 'Central Place');
      expect(_t(tester, 'station-name-other'), 'सेंट्रल प्लेस');
      expect(key('station-interchange'), findsOneWidget);
      expect(_t(tester, 'station-status'), 'Status: Open');
      // two lines, each with its own code
      expect(find.text('Test Red Line · CP'), findsOneWidget);
      expect(find.text('Test Blue Line · CP'), findsOneWidget);
      // aliases
      expect(find.text('Old Central'), findsOneWidget);
      expect(key('station-aliases'), findsOneWidget);
      // services that stop here
      expect(key('station-services'), findsOneWidget);
      expect(find.text('red-main'), findsOneWidget);
      // coordinates: index 2 of the invented list
      expect(_t(tester, 'station-coordinates'), '28.50200, 77.10000');
      expect(_t(tester, 'station-source'), startsWith('Source: test-fixture'));
    });

    testWidgets('single-line station is not called an interchange', (
      tester,
    ) async {
      await pumpApp(tester, location: '/station/beta');
      expect(key('station-one'), findsOneWidget);
      expect(key('station-interchange'), findsNothing);
    });

    testWidgets('no Hindi name: nothing is made up', (tester) async {
      await pumpApp(tester, location: '/station/xray');
      expect(_t(tester, 'station-name'), 'Xray Gate');
      expect(key('station-name-other'), findsNothing);
      // line with no code in the data shows the line name alone
      expect(find.text('Test Blue Line'), findsOneWidget);
    });

    testWidgets('Hindi interface: Hindi first, English second', (tester) async {
      await pumpApp(
        tester,
        locale: const Locale('hi'),
        location: '/station/central',
      );
      expect(_t(tester, 'station-name'), 'सेंट्रल प्लेस');
      expect(_t(tester, 'station-name-other'), 'Central Place');
    });

    testWidgets('closed station says closed', (tester) async {
      await pumpApp(tester, location: '/station/halt');
      expect(_t(tester, 'station-status'), 'Status: Closed');
    });

    testWidgets('platforms, gates, facilities, accessibility: not invented', (
      tester,
    ) async {
      await pumpApp(tester, location: '/station/central');
      for (final k in [
        'station-platforms',
        'station-gates',
        'station-facilities',
        'station-accessibility',
      ]) {
        expect(
          find.descendant(
            of: key(k),
            matching: find.text('Not in the data yet.'),
          ),
          findsOneWidget,
          reason: k,
        );
      }
    });

    testWidgets('invalid stored coordinates are not shown as a place', (
      tester,
    ) async {
      final base = demoNetwork();
      final s = base.station('beta')!;
      final snap = base.copyWith(
        stations: [
          for (final x in base.stations)
            x.id == 'beta'
                ? Station(
                    id: s.id,
                    nameEn: s.nameEn,
                    nameHi: s.nameHi,
                    lat: double.nan,
                    lng: 200,
                    status: s.status,
                    provenance: s.provenance,
                  )
                : x,
        ],
      );
      await pumpApp(tester, snapshot: snap, location: '/station/beta');
      expect(_t(tester, 'station-coordinates'), contains('No usable'));
      expect(find.textContaining('NaN'), findsNothing);
    });

    testWidgets('records in the dataset are shown; unknown (null) is left '
        'out, never turned into "No"', (tester) async {
      final base = demoNetwork();
      final snap = base.copyWith(
        platforms: const [
          core.Platform(
            stationId: 'central',
            lineId: 'red',
            number: '2A',
            provenance: testProvenance,
          ),
        ],
        gates: const [
          Gate(
            id: 'central:g1',
            stationId: 'central',
            number: 1,
            nameEn: 'North',
            hasLift: true,
            provenance: testProvenance,
          ),
        ],
        facilities: const [
          Facility(
            stationId: 'central',
            type: FacilityType.toilet,
            locationEn: 'Concourse',
            provenance: testProvenance,
          ),
        ],
        accessibility: const [
          Accessibility(
            stationId: 'central',
            lifts: 2,
            provenance: testProvenance,
          ),
        ],
      );
      await pumpApp(tester, snapshot: snap, location: '/station/central');
      expect(find.text('Platform 2A · Test Red Line'), findsOneWidget);
      expect(find.text('Gate 1 · North · Lift: Yes'), findsOneWidget);
      expect(find.text('Toilet · Concourse'), findsOneWidget);
      expect(find.text('Lifts: 2'), findsOneWidget);
      // unknown flags: no row at all
      expect(find.textContaining('Tactile'), findsNothing);
      expect(find.textContaining('Wheelchair'), findsNothing);
      expect(find.textContaining('Ramp'), findsNothing);
      expect(find.textContaining('Escalator'), findsNothing);
      expect(find.text('Not in the data yet.'), findsNothing);
    });

    testWidgets('provenance footer carries the check date when there is one', (
      tester,
    ) async {
      final base = demoNetwork();
      final s = base.station('beta')!;
      final snap = base.copyWith(
        stations: [
          for (final x in base.stations)
            x.id == 'beta'
                ? Station(
                    id: s.id,
                    nameEn: s.nameEn,
                    nameHi: s.nameHi,
                    lat: s.lat,
                    lng: s.lng,
                    status: s.status,
                    provenance: const Provenance(
                      sourceId: 'src-x',
                      confidence: Confidence.verified,
                      verifiedOn: '2026-09-01',
                    ),
                  )
                : x,
        ],
      );
      await pumpApp(tester, snapshot: snap, location: '/station/beta');
      expect(
        _t(tester, 'station-source'),
        'Source: src-x · verified · checked 2026-09-01',
      );
    });
  });

  group('navigation', () {
    testWidgets('picker row: info opens the detail by id, picking still '
        'returns the id', (tester) async {
      final c = await pumpApp(tester);
      await tester.tap(key('field-from'));
      await tester.pumpAndSettle();
      await tester.enterText(key('picker-field'), 'old central');
      await tester.pumpAndSettle();
      await tester.tap(key('station-info-central'));
      await tester.pumpAndSettle();
      expect(_t(tester, 'station-name'), 'Central Place');
      // back to the picker, which is still open
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(key('picker-field'), findsOneWidget);
      await tester.tap(key('station-option-central'));
      await tester.pumpAndSettle();
      expect(selection(c).fromId, 'central');
    });

    testWidgets('home: a chosen station has an info button', (tester) async {
      await pumpApp(tester);
      await pickStation(tester, JourneyEnd.from, 'beta', 'beta');
      await tester.tap(key('field-info-from'));
      await tester.pumpAndSettle();
      expect(_t(tester, 'station-name'), 'Beta Nagar');
    });

    testWidgets('route results: header names and listed stops open the '
        'detail', (tester) async {
      final c = await pumpApp(
        tester,
        location: '/go/route?from=alpha&to=delta',
      );
      await tester.tap(key('open-to'));
      await tester.pumpAndSettle();
      expect(_t(tester, 'station-name'), 'Delta Vihar');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(key('ride-toggle-0'));
      await tester.pumpAndSettle();
      await tester.tap(key('stop-0-beta'));
      await tester.pumpAndSettle();
      expect(_t(tester, 'station-name'), 'Beta Nagar');
      expect(routerOf(c).state.uri.path, '/station/beta');
    });

    testWidgets('route results: an unknown id is not a link', (tester) async {
      await pumpApp(tester, location: '/go/route?from=alpha&to=Delta%20Vihar');
      await tester.tap(key('open-to'));
      await tester.pumpAndSettle();
      expect(key('station-name'), findsNothing);
      expect(key('route-unknown'), findsOneWidget);
    });

    testWidgets('route from here / to here fill the journey on Home', (
      tester,
    ) async {
      final c = await pumpApp(tester, location: '/station/alpha');
      await tester.tap(key('route-from-here'));
      await tester.pumpAndSettle();
      expect(selection(c).fromId, 'alpha');
      expect(selection(c).toId, isNull);

      unawaited(routerOf(c).push<void>('/station/delta'));
      await tester.pumpAndSettle();
      await tester.tap(key('route-to-here'));
      await tester.pumpAndSettle();
      expect(selection(c).fromId, 'alpha');
      expect(selection(c).toId, 'delta');
      expect(
        tester.widget<FilledButton>(key('find-route')).onPressed,
        isNotNull,
      );
    });
  });
}
