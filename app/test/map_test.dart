import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/features/map/application/map_camera.dart';
import 'package:metromitra/features/map/application/map_overlay.dart';
import 'package:metromitra/features/map/application/map_provider.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

String _t(WidgetTester tester, String k) =>
    (tester.widget(key(k)) as Text).data ?? '';

// Colours the invented dataset gives its lines (never the app theme).
const red = Color(0xFFC62828);
const blue = Color(0xFF1565C0);
const green = Color(0xFF2E7D32);

/// What the map painted, recorded on a canvas without drawing pixels.
class Drawn {
  Drawn(TestRecordingCanvas canvas, Offset origin) {
    for (final call in canvas.invocations) {
      final name = call.invocation.memberName;
      final args = call.invocation.positionalArguments;
      if (name == #drawLine) {
        final paint = args[2] as Paint;
        lines.add((
          (args[0] as Offset) + origin,
          (args[1] as Offset) + origin,
          paint.color,
          paint.strokeWidth,
        ));
      } else if (name == #drawCircle) {
        final paint = args[2] as Paint;
        circles.add((
          (args[0] as Offset) + origin,
          args[1] as double,
          paint.color,
          paint.style,
        ));
      }
    }
  }

  final lines = <(Offset, Offset, Color, double)>[];
  final circles = <(Offset, double, Color, PaintingStyle)>[];

  bool hasLine({Color? color, double? width}) => lines.any(
    (l) =>
        (color == null || l.$3.toARGB32() == color.toARGB32()) &&
        (width == null || l.$4 == width),
  );

  bool hasCircle(Offset at, {double? radius}) => circles.any(
    (c) =>
        (c.$1 - at).distance < 0.5 &&
        (radius == null || (c.$2 - radius).abs() < 0.01),
  );
}

MetroSnapshot _withStations(
  MetroSnapshot base,
  Station Function(Station) change,
) => base.copyWith(stations: [for (final s in base.stations) change(s)]);

Station _moved(Station s, {double? lat, double? lng}) => Station(
  id: s.id,
  nameEn: s.nameEn,
  nameHi: s.nameHi,
  lat: lat ?? s.lat,
  lng: lng ?? s.lng,
  status: s.status,
  provenance: s.provenance,
);

void main() {
  final demo = demoNetwork();
  final geo = MapGeometry.fromSnapshot(demo);

  group('initialisation', () {});

  group('stations by canonical id', () {});

  group('drawing', () {});

  group('offline', () {
    testWidgets('the map and the route map never open a connection', (
      tester,
    ) async {
      final previous = HttpOverrides.current;
      final guard = _NoNetwork();
      HttpOverrides.global = guard;
      addTearDown(() => HttpOverrides.global = previous);
      await pumpApp(tester, location: '/map');
      await tester.tap(key('map-zoom-in'));
      await pumpApp(tester, location: '/go/route/map?from=alpha&to=yankee');
      expect(key('map-route-canvas'), findsOneWidget);
      expect(guard.attempts, 0);
    });
  });

  group('invalid and missing coordinates', () {
    testWidgets('no usable coordinates at all: an explicit empty state', (
      tester,
    ) async {
      final snap = _withStations(demo, (s) => _moved(s, lat: double.nan));
      await pumpApp(tester, snapshot: snap, location: '/map');
      expect(key('map-empty'), findsOneWidget);
      expect(find.textContaining('no stations with usable'), findsOneWidget);
      expect(key('map-canvas'), findsNothing);
    });

    testWidgets('an empty network', (tester) async {
      final snap = demo.copyWith(stations: const []);
      await pumpApp(tester, snapshot: snap, location: '/map');
      expect(key('map-empty'), findsOneWidget);
      expect(find.text('The installed data has no stations.'), findsOneWidget);
    });
  });

  group('framing', () {
    test('whole network: every station inside the padded view', () {
      final frame = geo.networkFrame!;
      for (final size in const [Size(360, 640), Size(800, 400), Size(50, 50)]) {
        final v = MapViewport(
          frame: frame,
          width: size.width,
          height: size.height,
        );
        for (final s in geo.stations) {
          final (x, y) = v.toBase(s.x, s.y);
          expect(x, inInclusiveRange(0, size.width));
          expect(y, inInclusiveRange(0, size.height));
        }
      }
    });

    test('same inputs, same pixels', () {
      final a = MapViewport(frame: geo.networkFrame!, width: 360, height: 640);
      final b = MapViewport(
        frame: MapGeometry.fromSnapshot(demoNetwork()).networkFrame!,
        width: 360,
        height: 640,
      );
      expect(a.baseScale, b.baseScale);
      expect(a.toBase(0.001, 0.002), b.toBase(0.001, 0.002));
    });

    test('identical coordinates frame to a finite, non-zero view', () {
      final snap = _withStations(
        demo,
        (s) => _moved(s, lat: 28.5, lng: 77.1),
      );
      final g = MapGeometry.fromSnapshot(snap);
      final f = g.networkFrame!;
      expect(f.width, greaterThan(0));
      final v = MapViewport(frame: f, width: 360, height: 640);
      expect(v.baseScale.isFinite, isTrue);
      expect(
        v.toBase(g.stations.first.x, g.stations.first.y).$1.isFinite,
        isTrue,
      );
    });

    test('camera: zoom keeps the point under the finger', () {
      final v = MapViewport(frame: geo.networkFrame!, width: 360, height: 640);
      final cam = MapCamera();
      const f = Offset(100, 200);
      final before = cam.unapply(v, f.dx, f.dy);
      cam.zoomAbout(v, 4, f.dx, f.dy);
      final after = cam.unapply(v, f.dx, f.dy);
      expect(after.$1, closeTo(before.$1, 1e-9));
      expect(after.$2, closeTo(before.$2, 1e-9));
      cam.zoomAbout(v, 1000, f.dx, f.dy);
      expect(cam.zoom, MapCamera.maxZoom);
      cam.zoomAbout(v, 0.0001, f.dx, f.dy);
      expect(cam.zoom, MapCamera.minZoom);
    });
  });

  group('route overlay (pure)', () {
    Itinerary plan(String from, String to, {int option = 0}) {
      final r = RoutePlanner(demo).plan(from, to);
      return r.itineraries[option];
    }

    test('rides: segments, stations and lines in order', () {
      final o = overlayFor(geo, plan('alpha', 'delta'));
      expect(o.lineIds, ['red']);
      expect(o.routeStationIds, ['alpha', 'beta', 'central', 'delta']);
      expect(o.highlightedSegments, {
        'red|alpha|beta',
        'red|beta|central',
        'red|central|delta',
      });
      expect(o.transferStationIds, isEmpty);
      expect(o.walks, isEmpty);
      expect((o.fromId, o.toId), ('alpha', 'delta'));
    });

    test('a change is a transfer station; both lines are highlighted', () {
      final o = overlayFor(geo, plan('alpha', 'yankee'));
      expect(o.lineIds, ['red', 'blue']);
      expect(o.transferStationIds, ['central']);
      expect(
        o.highlightedSegments,
        containsAll(['red|beta|central', 'blue|central|yankee']),
      );
    });

    test('a walk appears only when the route contains one', () {
      final walk = overlayFor(geo, plan('alpha', 'gamut'));
      expect(walk.walks, [('echo', 'gamma')]);
      expect(overlayFor(geo, plan('alpha', 'echo')).walks, isEmpty);
    });

    test('a walk with an undrawable end is not drawn', () {
      final snap = _withStations(
        demo,
        (s) => s.id == 'gamma' ? _moved(s, lat: double.nan) : s,
      );
      final g = MapGeometry.fromSnapshot(snap);
      final o = overlayFor(
        g,
        RoutePlanner(snap).plan('alpha', 'gamut').itineraries.first,
      );
      expect(o.walks, isEmpty);
      expect(o.routeStationIds, isNot(contains('gamma')));
    });

    test('same itinerary, same overlay (deterministic)', () {
      final a = overlayFor(geo, plan('alpha', 'yankee'));
      final b = overlayFor(
        MapGeometry.fromSnapshot(demoNetwork()),
        plan('alpha', 'yankee'),
      );
      expect(a.routeStationIds, b.routeStationIds);
      expect(
        a.highlightedSegments.toList()..sort(),
        b.highlightedSegments.toList()..sort(),
      );
    });
  });

  group('route on the map', () {
    testWidgets('a walk between stations is shown only when in the route', (
      tester,
    ) async {
      await pumpApp(tester, location: '/go/route/map?from=alpha&to=gamut');
      expect(key('map-legend-walk'), findsOneWidget);
      expect(
        find.textContaining('not a walking path'),
        findsOneWidget,
        reason: 'the dashed link is a straight link, no invented path',
      );
      // no duration or distance for the walk anywhere on the map screen
      expect(find.textContaining(' m walk'), findsNothing);
    });

    testWidgets('approximate time warning is the same as in the results', (
      tester,
    ) async {
      await pumpApp(tester, location: '/go/route/map?from=alpha&to=delta');
      expect(_t(tester, 'map-route-duration'), startsWith('About '));
      expect(key('map-approx-notice'), findsOneWidget);
    });

    testWidgets('route map for the option chosen on the results screen', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        location: '/go/route?from=alpha&to=zulu',
      );
      expect(key('alt-1'), findsOneWidget);
      await tester.tap(key('alt-1'));
      await tester.pumpAndSettle();
      await tester.tap(key('show-route-on-map'));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/go/route/map');
      expect(routerOf(c).state.uri.queryParameters['opt'], '1');
      expect(key('map-route-canvas'), findsOneWidget);
    });
  });

  group('error states', () {
    testWidgets('unknown station id', (tester) async {
      await pumpApp(tester, location: '/map?station=nope');
      expect(key('map-station-not-found'), findsOneWidget);
      await tester.tap(key('map-show-whole'));
      await tester.pumpAndSettle();
      expect(key('map-canvas'), findsOneWidget);
    });

    testWidgets('a name is not an id', (tester) async {
      await pumpApp(tester, location: '/map?station=Alpha%20Chowk');
      expect(key('map-station-not-found'), findsOneWidget);
    });

    testWidgets('station without coordinates', (tester) async {
      final snap = _withStations(
        demo,
        (s) => s.id == 'beta' ? _moved(s, lat: double.nan) : s,
      );
      await pumpApp(tester, snapshot: snap, location: '/map?station=beta');
      expect(key('map-station-no-coordinates'), findsOneWidget);
    });

    testWidgets('route not found / unreachable / unknown ids', (tester) async {
      for (final q in [
        'from=alpha&to=isle-a',
        'from=alpha&to=nope',
        'from=alpha&to=alpha',
        'from=&to=',
      ]) {
        await pumpApp(tester, location: '/go/route/map?$q');
        expect(key('map-route-not-found'), findsOneWidget, reason: q);
      }
    });

    testWidgets('a route with nothing drawable', (tester) async {
      final snap = _withStations(
        demo,
        (s) =>
            ['alpha', 'beta'].contains(s.id) ? _moved(s, lat: double.nan) : s,
      );
      await pumpApp(
        tester,
        snapshot: snap,
        location: '/go/route/map?from=alpha&to=beta',
      );
      expect(key('map-route-no-geometry'), findsOneWidget);
    });

    testWidgets('a failing geometry build shows "map unavailable"', (
      tester,
    ) async {
      await pumpApp(
        tester,
        location: '/map',
        extraOverrides: [
          mapGeometryProvider.overrideWith((ref) => throw StateError('boom')),
        ],
      );
      expect(key('map-unavailable'), findsOneWidget);
      expect(find.text('The map cannot be shown'), findsOneWidget);
    });

    testWidgets('the route map also survives a failing geometry build', (
      tester,
    ) async {
      await pumpApp(
        tester,
        location: '/go/route/map?from=alpha&to=beta',
        extraOverrides: [
          mapGeometryProvider.overrideWith((ref) => throw StateError('boom')),
        ],
      );
      expect(key('map-unavailable'), findsOneWidget);
    });
  });

  group('entry points', () {
    testWidgets('Station detail: Show on map frames that station', (
      tester,
    ) async {
      final c = await pumpApp(tester, location: '/station/central');
      await tester.tap(key('show-on-map'));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/map');
      expect(routerOf(c).state.uri.queryParameters['station'], 'central');
      expect(key('map-canvas'), findsOneWidget);
    });

    testWidgets('Hindi interface draws the same map', (tester) async {
      await pumpApp(tester, locale: const Locale('hi'), location: '/map');
      expect(key('map-canvas'), findsOneWidget);
      expect(find.text('मेट्रो नक्शा'), findsWidgets);
    });
  });

  group('determinism', () {
    test('the geometry does not depend on the order of the dataset lists', () {
      final shuffled = demo.copyWith(
        stations: demo.stations.reversed.toList(),
        serviceStops: demo.serviceStops.reversed.toList(),
        stationLines: demo.stationLines.reversed.toList(),
        lines: demo.lines.reversed.toList(),
      );
      final a = MapGeometry.fromSnapshot(demo);
      final b = MapGeometry.fromSnapshot(shuffled);
      expect(
        a.stations.map((s) => '${s.id}:${s.x}:${s.y}:${s.lineIds}').toList(),
        b.stations.map((s) => '${s.id}:${s.x}:${s.y}:${s.lineIds}').toList(),
      );
      expect(
        a.segments.map((s) => s.key).toList(),
        b.segments.map((s) => s.key).toList(),
      );
      expect(a.networkFrame.toString(), b.networkFrame.toString());
    });
  });

  group('larger invented network', () {});
}

/// Fails the test if anything tries to open an HTTP connection.
class _NoNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('network access is not allowed in this test');
  }
}
