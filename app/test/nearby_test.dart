import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/shared/location/location_source.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

// demoNetwork places station i at lat 28.5 + i * 0.001, lng 77.1
// (alpha 28.500, beta 28.501, central 28.502, ...): about 111 m apart.
const _atAlpha = LocationFix(lat: 28.5, lng: 77.1);

String _t(WidgetTester tester, String k) =>
    (tester.widget(key(k)) as Text).data ?? '';

Future<FakeLocationSource> _open(
  WidgetTester tester,
  LocationResult result, {
  MetroSnapshot? snapshot,
  bool tap = true,
}) async {
  final source = FakeLocationSource(result);
  await pumpApp(
    tester,
    snapshot: snapshot,
    locationSource: source,
    location: '/go/nearby',
  );
  if (tap) {
    await tester.tap(key('nearby-use-location'));
    await tester.pumpAndSettle();
  }
  return source;
}

Station _at(String id, double lat, double lng) => Station(
  id: id,
  nameEn: 'Pt $id',
  lat: lat,
  lng: lng,
  status: OperatingStatus.open,
  provenance: testProvenance,
);

void main() {
  group('permission and privacy', () {
    testWidgets('location is not requested until the user asks', (
      tester,
    ) async {
      final source = await _open(tester, _atAlpha, tap: false);
      expect(key('nearby-idle'), findsOneWidget);
      expect(find.textContaining('not saved or sent'), findsOneWidget);
      expect(source.calls, 0);
      await tester.tap(key('nearby-use-location'));
      await tester.pumpAndSettle();
      expect(source.calls, 1);
    });

    testWidgets('opening Home or other screens never asks for location', (
      tester,
    ) async {
      final source = FakeLocationSource(_atAlpha);
      await pumpApp(tester, locationSource: source);
      await tester.tap(key('field-from'));
      await tester.pumpAndSettle();
      expect(source.calls, 0);
    });

    testWidgets('the position is dropped when the screen closes', (
      tester,
    ) async {
      final source = await _open(tester, _atAlpha);
      expect(key('nearby-results'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(key('nearby'));
      await tester.pumpAndSettle();
      // back to the explanation, nothing remembered, nothing re-requested
      expect(key('nearby-idle'), findsOneWidget);
      expect(key('nearby-results'), findsNothing);
      expect(source.calls, 1);
    });

    testWidgets('denied: explained, with a way to pick a station by name', (
      tester,
    ) async {
      await _open(tester, const LocationDenied());
      expect(key('nearby-denied'), findsOneWidget);
      expect(key('nearby-retry'), findsOneWidget);
      await tester.tap(key('nearby-pick'));
      await tester.pumpAndSettle();
      await tester.enterText(key('picker-field'), 'delta');
      await tester.pumpAndSettle();
      await tester.tap(key('station-option-delta'));
      await tester.pumpAndSettle();
      expect(_t(tester, 'station-name'), 'Delta Vihar');
    });

    testWidgets('denied for good: settings button, no pointless retry', (
      tester,
    ) async {
      final source = await _open(tester, const LocationDenied(permanent: true));
      expect(key('nearby-retry'), findsNothing);
      await tester.tap(key('nearby-open-settings'));
      expect(source.settingsOpened, 1);
    });

    testWidgets('unavailable: can retry, and a retry can succeed', (
      tester,
    ) async {
      final source = await _open(tester, const LocationUnavailable());
      expect(key('nearby-unavailable'), findsOneWidget);
      source.result = _atAlpha;
      await tester.tap(key('nearby-retry'));
      await tester.pumpAndSettle();
      expect(key('nearby-results'), findsOneWidget);
      expect(source.calls, 2);
    });

    testWidgets('location services off: says so and opens its settings', (
      tester,
    ) async {
      final source = await _open(
        tester,
        const LocationUnavailable(servicesOff: true),
      );
      expect(key('nearby-services-off'), findsOneWidget);
      await tester.tap(key('nearby-open-location-settings'));
      expect(source.locationSettingsOpened, 1);
    });

    for (final (name, bad) in [
      ('not a number', const LocationFix(lat: double.nan, lng: 77.1)),
      ('latitude out of range', const LocationFix(lat: 95, lng: 77.1)),
      (
        'infinite longitude',
        const LocationFix(lat: 28.5, lng: double.infinity),
      ),
      ('0,0 (no fix)', const LocationFix(lat: 0, lng: 0)),
    ]) {
      testWidgets('an unusable position is reported, not used: $name', (
        tester,
      ) async {
        await _open(tester, bad);
        expect(key('nearby-invalid'), findsOneWidget);
        expect(key('nearby-results'), findsNothing);
        expect(key('nearby-pick'), findsOneWidget);
      });
    }
  });

  group('results', () {
    testWidgets('nearest first, straight-line labelled, open stations only', (
      tester,
    ) async {
      await _open(tester, _atAlpha);
      expect(key('nearby-results'), findsOneWidget);
      expect(find.textContaining('straight line'), findsWidgets);
      expect(_t(tester, 'nearby-straight-note'), contains('not walking'));
      expect(_t(tester, 'nearby-distance-alpha'), '0 m in a straight line');
      expect(_t(tester, 'nearby-distance-beta'), '111 m in a straight line');
      expect(_t(tester, 'nearby-distance-central'), '222 m in a straight line');
      // 10 rows at most; the closed station is never offered
      expect(find.byKey(const Key('nearby-row-halt')), findsNothing);

      final order = [
        for (final id in ['alpha', 'beta', 'central', 'delta'])
          tester.getTopLeft(key('nearby-row-$id')).dy,
      ];
      expect(order, [...order]..sort());
    });

    testWidgets('kilometres for longer distances', (tester) async {
      // 0.02 deg latitude ~ 2.2 km north of the first station
      await _open(tester, const LocationFix(lat: 28.48, lng: 77.1));
      expect(_t(tester, 'nearby-distance-alpha'), '2.2 km in a straight line');
    });

    testWidgets('rows show lines and open the station by canonical id', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        locationSource: FakeLocationSource(
          const LocationFix(lat: 28.502, lng: 77.1),
        ),
        location: '/go/nearby',
      );
      await tester.tap(key('nearby-use-location'));
      await tester.pumpAndSettle();
      for (final line in ['Test Red Line', 'Test Blue Line']) {
        expect(
          find.descendant(
            of: key('nearby-row-central'),
            matching: find.text(line),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(key('nearby-row-central'));
      await tester.pumpAndSettle();
      expect(_t(tester, 'station-name'), 'Central Place');
      expect(routerOf(c).state.uri.path, '/station/central');
    });

    testWidgets('equal distances: ordered by station id, stable', (
      tester,
    ) async {
      final base = demoNetwork();
      // two stations exactly the same distance either side of the fix,
      // listed in the "wrong" order
      final snap = base.copyWith(
        stations: [
          _at('zz-tie', 28.5005, 77.1),
          _at('aa-tie', 28.4995, 77.1),
          _at('mid-tie', 28.5, 77.1005),
        ],
      );
      await _open(
        tester,
        const LocationFix(lat: 28.5, lng: 77.1),
        snapshot: snap,
      );
      final order = [
        for (final id in ['aa-tie', 'zz-tie'])
          tester.getTopLeft(key('nearby-row-$id')).dy,
      ];
      expect(
        _t(tester, 'nearby-distance-aa-tie'),
        _t(tester, 'nearby-distance-zz-tie'),
      );
      expect(order[0] < order[1], isTrue);
    });

    testWidgets('a station with invalid coordinates is skipped', (
      tester,
    ) async {
      final base = demoNetwork();
      final snap = base.copyWith(
        stations: [
          _at('ok', 28.5, 77.1),
          _at('nan', double.nan, 77.1),
          _at('big', 120, 77.1),
        ],
      );
      await _open(tester, _atAlpha, snapshot: snap);
      expect(key('nearby-row-ok'), findsOneWidget);
      expect(key('nearby-row-nan'), findsNothing);
      expect(key('nearby-row-big'), findsNothing);
    });

    testWidgets('approximate positions are labelled', (tester) async {
      await _open(
        tester,
        const LocationFix(lat: 28.5, lng: 77.1, isApproximate: true),
      );
      expect(key('nearby-approximate'), findsOneWidget);
    });

    testWidgets('a precise position carries no approximate label', (
      tester,
    ) async {
      await _open(tester, _atAlpha);
      expect(key('nearby-approximate'), findsNothing);
    });

    testWidgets('zero stations nearby: an explicit empty state', (
      tester,
    ) async {
      await _open(tester, const LocationFix(lat: 19.07, lng: 72.87));
      expect(key('nearby-none'), findsOneWidget);
      expect(find.textContaining('5 km'), findsOneWidget);
      expect(key('nearby-pick'), findsOneWidget);
    });

    testWidgets('Hindi interface', (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('hi')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await _open(tester, _atAlpha);
      expect(_t(tester, 'nearby-distance-beta'), 'सीधी रेखा में 111 मी');
    });
  });

  group('entry from Home', () {
    testWidgets('the Nearby button opens the screen', (tester) async {
      await pumpApp(tester, locationSource: FakeLocationSource(_atAlpha));
      await tester.tap(key('nearby'));
      await tester.pumpAndSettle();
      expect(key('nearby-idle'), findsOneWidget);
    });
  });
}
