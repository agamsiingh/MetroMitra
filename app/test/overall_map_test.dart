import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/map/application/map_provider.dart';
import 'package:metromitra/features/map/presentation/overview_map.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

/// The base drawing (lines, stations, labels) of the Map tab.
OverviewPainter _drawing(WidgetTester tester) {
  final render =
      tester.renderObject(
            find
                .descendant(
                  of: key('map-canvas'),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          as RenderCustomPaint;
  return render.painter! as OverviewPainter;
}

/// The marks laid over it (journey ends, search hit, live position).
OverviewMarksPainter _marks(WidgetTester tester) {
  final render =
      tester.renderObject(key('overview-marks')) as RenderCustomPaint;
  return render.painter! as OverviewMarksPainter;
}

Matrix4 _view(WidgetTester tester) => tester
    .widget<InteractiveViewer>(key('overview-viewer'))
    .transformationController!
    .value;

/// Where a station is on screen right now (drawing point through the zoom).
Offset _onScreen(WidgetTester tester, String id) {
  final p = _drawing(tester).layout.points[id]!;
  return tester.getTopLeft(key('overview-viewer')) +
      MatrixUtils.transformPoint(_view(tester), p);
}

/// Circles the marks painter drew.
List<(Offset, Color)> _markCircles(WidgetTester tester) {
  final render =
      tester.renderObject(key('overview-marks')) as RenderCustomPaint;
  final canvas = TestRecordingCanvas();
  render.painter!.paint(canvas, render.size);
  return [
    for (final c in canvas.invocations)
      if (c.invocation.memberName == #drawCircle)
        (
          c.invocation.positionalArguments[0] as Offset,
          (c.invocation.positionalArguments[2] as Paint).color,
        ),
  ];
}

void main() {
  final demo = demoNetwork();

  group('the Map tab is the overall map', () {
    testWidgets('opens by itself with every station named and all controls', (
      tester,
    ) async {
      await pumpApp(tester, location: '/map');
      expect(key('map-canvas'), findsOneWidget);
      for (final k in [
        'map-zoom-in',
        'map-zoom-out',
        'map-reset',
        'map-search',
        'map-track',
      ]) {
        expect(key(k), findsOneWidget, reason: k);
      }
      // the rough geographic map and its button are gone
      expect(key('map-overview'), findsNothing);
      expect(key('map-route-canvas'), findsNothing);
      expect(_drawing(tester).layout.labels, isNotEmpty);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').startsWith(
                'Metro map with 24 stations',
              ),
        ),
        findsOneWidget,
      );
      expect(key('overview-legend'), findsOneWidget);
      expect(key('overview-not-to-scale'), findsOneWidget);
      expect(find.textContaining('Map data: TEST DATA'), findsOneWidget);
    });

    testWidgets('the whole network fits the screen at first', (tester) async {
      await pumpApp(tester, location: '/map');
      final layout = _drawing(tester).layout;
      final box = tester.getRect(key('overview-viewer'));
      for (final id in ['alpha', 'zulu', 'delta']) {
        final p = _onScreen(tester, id);
        expect(box.contains(p), isTrue, reason: '$id at $p inside $box');
      }
      expect(layout.points.length, greaterThan(10));
      // a nearly straight network must not shrink the map to a speck
      expect(_view(tester).entry(0, 0), greaterThan(0.05));
      expect(layout.size.height, lessThanOrEqualTo(overviewWidth * 3));
    });

    testWidgets('closed stations are still drawn (the data has them)', (
      tester,
    ) async {
      await pumpApp(tester, location: '/map');
      expect(_drawing(tester).layout.points.containsKey('halt'), isTrue);
    });
  });

  group('stations by canonical id', () {
    testWidgets('tapping a station opens its detail, by id', (tester) async {
      final c = await pumpApp(tester, location: '/map');
      for (final (id, name) in [
        ('alpha', 'Alpha Chowk'),
        ('delta', 'Delta Vihar'),
        ('zulu', 'Zulu Terminal'),
      ]) {
        await tester.tapAt(_onScreen(tester, id));
        await tester.pumpAndSettle();
        expect(routerOf(c).state.uri.path, '/station/$id');
        expect(
          (tester.widget(key('station-name')) as Text).data,
          name,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('same-named stations are told apart by id', (tester) async {
      final c = await pumpApp(tester, location: '/map');
      for (final id in ['twin-1', 'twin-2']) {
        await tester.tapAt(_onScreen(tester, id));
        await tester.pumpAndSettle();
        expect(routerOf(c).state.uri.path, '/station/$id');
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('tapping empty space does nothing', (tester) async {
      final c = await pumpApp(tester, location: '/map');
      final box = tester.getRect(key('overview-viewer'));
      await tester.tapAt(box.topLeft + const Offset(3, 3));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/map');
    });
  });

  group('operations', () {
    testWidgets('zoom buttons change the view; fit puts it back', (
      tester,
    ) async {
      await pumpApp(tester, location: '/map');
      final fit = _view(tester).entry(0, 0);
      await tester.tap(key('map-zoom-in'));
      await tester.pumpAndSettle();
      final zoomed = _view(tester).entry(0, 0);
      expect(zoomed, closeTo(fit * 1.6, 1e-6));
      await tester.tap(key('map-zoom-out'));
      await tester.tap(key('map-zoom-out'));
      await tester.pumpAndSettle();
      expect(_view(tester).entry(0, 0), lessThan(fit));
      await tester.tap(key('map-reset'));
      await tester.pumpAndSettle();
      expect(_view(tester).entry(0, 0), closeTo(fit, 1e-6));
    });

    testWidgets('selected origin and destination are ringed', (tester) async {
      final c = await pumpApp(tester, location: '/map');
      c.read(journeyProvider.notifier)
        ..set(JourneyEnd.from, 'beta')
        ..set(JourneyEnd.to, 'delta');
      await tester.pumpAndSettle();
      final m = _marks(tester);
      final points = _drawing(tester).layout.points;
      expect(m.fromId, 'beta');
      expect(m.toId, 'delta');
      final rings = _markCircles(tester).map((e) => e.$1).toList();
      expect(rings, contains(points['beta']));
      expect(rings, contains(points['delta']));
    });

    testWidgets('?station=<id> opens centred on that station', (tester) async {
      await pumpApp(tester, location: '/map?station=central');
      final box = tester.getRect(key('overview-viewer'));
      final p = _onScreen(tester, 'central');
      expect(p.dx, closeTo(box.center.dx, 1));
      expect(p.dy, closeTo(box.center.dy, 1));
    });

    testWidgets('search brings the station to the centre and marks it', (
      tester,
    ) async {
      await pumpApp(tester, location: '/map');
      await tester.tap(key('map-search'));
      await tester.pumpAndSettle();
      await tester.enterText(key('map-search-field'), 'delta');
      await tester.pumpAndSettle();
      await tester.tap(key('map-search-result-delta'));
      await tester.pumpAndSettle();
      expect(_marks(tester).highlightId, 'delta');
      final box = tester.getRect(key('overview-viewer'));
      final p = _onScreen(tester, 'delta');
      expect(p.dx, closeTo(box.center.dx, 1));
      expect(p.dy, closeTo(box.center.dy, 1));
      expect(_marks(tester).tags.keys, contains('delta'));
    });
  });

  group('invalid and missing coordinates', () {
    testWidgets('stations without a usable position are left out and said', (
      tester,
    ) async {
      Station moved(Station s, {double? lat, double? lng}) => Station(
        id: s.id,
        nameEn: s.nameEn,
        nameHi: s.nameHi,
        lat: lat ?? s.lat,
        lng: lng ?? s.lng,
        status: s.status,
        provenance: s.provenance,
      );
      final snap = demo.copyWith(
        stations: [
          for (final s in demo.stations)
            switch (s.id) {
              'isle-a' => moved(s, lat: double.nan),
              'isle-b' => moved(s, lat: 95),
              'xray' => moved(s, lat: 0, lng: 0),
              _ => s,
            },
        ],
      );
      final c = await pumpApp(tester, snapshot: snap, location: '/map');
      expect(
        (tester.widget(key('map-skipped-note')) as Text).data,
        contains('3 stations'),
      );
      expect(c.read(mapGeometryProvider).skippedStationIds, [
        'isle-a',
        'isle-b',
        'xray',
      ]);
      expect(_drawing(tester).layout.points.containsKey('isle-a'), isFalse);
      // the rest still works
      await tester.tapAt(_onScreen(tester, 'beta'));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/station/beta');
    });
  });

  group('larger invented network', () {
    testWidgets('1500 stations draw, never overlap labels, respond to a tap', (
      tester,
    ) async {
      final lineNames = ['red', 'blue', 'ring', 'green', 'island', 'slow'];
      final stations = [
        for (var i = 0; i < 1500; i++) TStation('p$i', 'Pt $i'),
      ];
      final services = [
        for (var l = 0; l < 6; l++)
          TService('svc$l', lineNames[l], [
            for (var i = 0; i < 250; i++) 'p${l * 250 + i}',
          ]),
      ];
      final snap = buildTestNetwork(stations: stations, services: services);
      final sw = Stopwatch()..start();
      final c = await pumpApp(tester, snapshot: snap, location: '/map');
      expect(_drawing(tester).layout.points, hasLength(1500));
      final rects = [
        for (final l in _drawing(tester).layout.labels)
          l.offset & Size(l.painter.width, l.painter.height),
      ];
      for (var i = 0; i < rects.length; i += 7) {
        for (var j = i + 1; j < rects.length; j += 7) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
      // zoomed in, so the tap lands on one station and nothing else
      await tester.tap(key('map-search'));
      await tester.pumpAndSettle();
      await tester.enterText(key('map-search-field'), 'Pt 777');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('map-search-result-p777')));
      await tester.pumpAndSettle();
      await tester.tapAt(_onScreen(tester, 'p777'));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/station/p777');
      // generous: guards against quadratic work, not machine speed
      expect(sw.elapsed, lessThan(const Duration(seconds: 60)));
    });
  });
}
