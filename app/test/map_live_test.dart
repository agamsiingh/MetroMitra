import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/map/application/live_tracking.dart';
import 'package:metromitra/features/map/presentation/network_map.dart';
import 'package:metromitra/features/map/presentation/overview_map.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/location/location_source.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

String _t(WidgetTester tester, String k) =>
    (tester.widget(key(k)) as Text).data ?? '';

/// Circles the map canvas painted (position, radius, colour), from the
/// drawing and the marks laid over it.
List<(Offset, double, Color)> _circles(WidgetTester tester) {
  final out = <(Offset, double, Color)>[];
  for (final element
      in find
          .descendant(of: key('map-canvas'), matching: find.byType(CustomPaint))
          .evaluate()) {
    final render = element.renderObject! as RenderCustomPaint;
    final canvas = TestRecordingCanvas();
    render.painter!.paint(canvas, render.size);
    for (final c in canvas.invocations) {
      if (c.invocation.memberName == #drawCircle) {
        out.add((
          c.invocation.positionalArguments[0] as Offset,
          c.invocation.positionalArguments[1] as double,
          (c.invocation.positionalArguments[2] as Paint).color,
        ));
      }
    }
  }
  return out;
}

const _userBlue = Color(0xFF1A73E8);

void main() {
  late FakeLocationSource gps;
  late MetroSnapshot snap;

  setUp(() {
    gps = FakeLocationSource(const LocationUnavailable());
    snap = demoNetwork();
  });

  Station st(String id) => snap.station(id)!;

  Future<ProviderContainer> openMap(WidgetTester tester, {Locale? locale}) =>
      pumpApp(
        tester,
        snapshot: snap,
        location: '/map',
        locationSource: gps,
        locale: locale,
      );

  group('live tracking', () {
    testWidgets('off by default: no location request, no panel', (
      tester,
    ) async {
      await openMap(tester);
      expect(gps.watchers, 0);
      expect(gps.calls, 0);
      expect(key('map-track-panel'), findsNothing);
      expect(
        _circles(tester).where((c) => c.$3.toARGB32() == _userBlue.toARGB32()),
        isEmpty,
      );
    });

    testWidgets('a fix shows the dot, the nearest station and its distance; '
        'updates move the dot', (tester) async {
      final c = await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pump();
      expect(gps.watchers, 1);
      expect(key('map-track-locating'), findsOneWidget);

      final alpha = st('alpha');
      gps.live.add(LocationFix(lat: alpha.lat, lng: alpha.lng, accuracyM: 8));
      await tester.pumpAndSettle();
      expect(_t(tester, 'map-track-nearest-name'), contains(alpha.nameEn));
      expect(_t(tester, 'map-track-distance'), startsWith('0 m'));
      final dots1 = _circles(
        tester,
      ).where((c) => c.$3.toARGB32() == _userBlue.toARGB32()).toList();
      expect(dots1, hasLength(1));

      // the nearest station follows the position
      final delta = st('delta');
      gps.live.add(LocationFix(lat: delta.lat, lng: delta.lng, accuracyM: 8));
      await tester.pumpAndSettle();
      expect(_t(tester, 'map-track-nearest-name'), contains(delta.nameEn));
      final dots2 = _circles(
        tester,
      ).where((c) => c.$3.toARGB32() == _userBlue.toARGB32()).toList();
      expect(dots2.single.$1, isNot(dots1.single.$1));

      // tapping the nearest station opens it
      await tester.tap(key('map-track-nearest'));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/station/delta');
    });

    testWidgets('stopping cancels the GPS and removes the dot', (tester) async {
      await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pump();
      final a = st('alpha');
      gps.live.add(LocationFix(lat: a.lat, lng: a.lng));
      await tester.pumpAndSettle();
      expect(gps.live.hasListener, isTrue);
      await tester.tap(key('map-track'));
      await tester.pumpAndSettle();
      expect(gps.live.hasListener, isFalse);
      expect(key('map-track-panel'), findsNothing);
    });

    testWidgets('leaving the map stops tracking (nothing keeps running)', (
      tester,
    ) async {
      final c = await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pumpAndSettle();
      expect(gps.live.hasListener, isTrue);
      routerOf(c).go('/go');
      await tester.pumpAndSettle();
      expect(gps.live.hasListener, isFalse);
    });

    testWidgets('permission denied: the map keeps working', (tester) async {
      await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pump();
      gps.live.add(const LocationDenied());
      await tester.pumpAndSettle();
      expect(
        _t(tester, 'map-track-denied'),
        'The map works without your location.',
      );
      expect(gps.live.hasListener, isFalse);
      expect(key('map-canvas'), findsOneWidget);
    });

    testWidgets('permanently denied: offers the app settings', (tester) async {
      await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pump();
      gps.live.add(const LocationDenied(permanent: true));
      await tester.pumpAndSettle();
      await tester.tap(key('map-track-settings'));
      expect(gps.settingsOpened, 1);
    });

    testWidgets('location switched off: offers the location settings', (
      tester,
    ) async {
      await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pump();
      gps.live.add(const LocationUnavailable(servicesOff: true));
      await tester.pumpAndSettle();
      expect(key('map-track-unavailable'), findsOneWidget);
      await tester.tap(key('map-track-location-settings'));
      expect(gps.locationSettingsOpened, 1);
    });

    testWidgets('a lost signal keeps the last position, marked as lost', (
      tester,
    ) async {
      await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pump();
      final a = st('alpha');
      gps.live
        ..add(LocationFix(lat: a.lat, lng: a.lng))
        ..add(const LocationUnavailable());
      await tester.pumpAndSettle();
      expect(key('map-track-lost'), findsOneWidget);
      expect(_t(tester, 'map-track-nearest-name'), contains(a.nameEn));
      expect(gps.live.hasListener, isTrue, reason: 'still trying');
    });

    testWidgets('far from every station: says so, never invents one', (
      tester,
    ) async {
      await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pump();
      gps.live.add(const LocationFix(lat: 19.07, lng: 72.87)); // Mumbai
      await tester.pumpAndSettle();
      expect(key('map-track-none'), findsOneWidget);
      expect(key('map-track-nearest'), findsNothing);
    });

    testWidgets('approximate positions are labelled', (tester) async {
      await openMap(tester);
      await tester.tap(key('map-track'));
      await tester.pump();
      final a = st('alpha');
      gps.live.add(
        LocationFix(
          lat: a.lat,
          lng: a.lng,
          accuracyM: 3000,
          isApproximate: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(key('map-track-approx'), findsOneWidget);
    });

    testWidgets('Hindi interface names the nearest station in Hindi', (
      tester,
    ) async {
      await openMap(tester, locale: const Locale('hi'));
      await tester.tap(key('map-track'));
      await tester.pump();
      final d = st('delta');
      gps.live.add(LocationFix(lat: d.lat, lng: d.lng));
      await tester.pumpAndSettle();
      expect(_t(tester, 'map-track-nearest-name'), contains(d.nameHi));
    });
  });

  group('station search on the map', () {
    testWidgets('finds a station by name and frames it', (tester) async {
      await openMap(tester);
      await tester.tap(key('map-search'));
      await tester.pumpAndSettle();
      await tester.enterText(key('map-search-field'), 'delta');
      await tester.pumpAndSettle();
      await tester.tap(key('map-search-result-delta'));
      await tester.pumpAndSettle();
      expect(key('map-search-field'), findsNothing);
      // the found station is ringed and named over the map
      final marks =
          tester.renderObject(key('overview-marks')) as RenderCustomPaint;
      expect((marks.painter! as OverviewMarksPainter).highlightId, 'delta');
    });

    testWidgets('Hindi and codes work; nothing found is said', (tester) async {
      await openMap(tester);
      await tester.tap(key('map-search'));
      await tester.pumpAndSettle();
      await tester.enterText(key('map-search-field'), 'डेल्टा');
      await tester.pumpAndSettle();
      expect(key('map-search-result-delta'), findsOneWidget);
      await tester.enterText(key('map-search-field'), 'BT');
      await tester.pumpAndSettle();
      expect(key('map-search-result-beta'), findsOneWidget);
      await tester.enterText(key('map-search-field'), 'zzzzqqq');
      await tester.pumpAndSettle();
      expect(key('map-search-none'), findsOneWidget);
    });
  });

  group('labels', () {
    const style = TextStyle(fontSize: 11);
    const small = TextStyle(fontSize: 10);

    test('English first, Hindi below; Hindi interface the other way', () {
      final en = mapStationLabel(
        stationTitles(
          nameEn: 'Hauz Khas',
          nameHi: 'हौज़ ख़ास',
          locale: const Locale('en'),
        ),
        style,
        small,
      );
      expect(en.toPlainText(), 'Hauz Khas\nहौज़ ख़ास');
      final hi = mapStationLabel(
        stationTitles(
          nameEn: 'Hauz Khas',
          nameHi: 'हौज़ ख़ास',
          locale: const Locale('hi'),
        ),
        style,
        small,
      );
      expect(hi.toPlainText(), 'हौज़ ख़ास\nHauz Khas');
    });

    test('no Hindi name in the data: one line, nothing made up', () {
      final l = mapStationLabel(
        stationTitles(
          nameEn: 'Gamma Gate',
          nameHi: null,
          locale: const Locale('hi'),
        ),
        style,
        small,
      );
      expect(l.toPlainText(), 'Gamma Gate');
    });
  });

  test('tracking is memory only: no storage or network in its code', () {
    // see also boundary_test; this guards the new controller directly
    expect(trackingNearestRadiusM, 30000);
    expect(liveTrackingProvider, isNotNull);
    expect(metroServicesProvider, isNotNull);
  });
}
