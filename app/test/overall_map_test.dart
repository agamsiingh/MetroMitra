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
OverviewPainter _drawing(WidgetTester tester, {String canvas = 'map-canvas'}) {
  final render =
      tester.renderObject(
            find
                .descendant(
                  of: key(canvas),
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
Offset _onScreen(
  WidgetTester tester,
  String id, {
  String canvas = 'map-canvas',
}) {
  final p = _drawing(tester, canvas: canvas).layout.points[id]!;
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
  group('route on the overall map', () {
    const canvas = 'map-route-canvas';
    const route = '/go/route/map?from=alpha&to=yankee';

    /// Lines (colour, width) and circles (centre, radius) the drawing painted.
    ({List<(Color, double)> lines, List<(Offset, double)> circles}) painted(
      WidgetTester tester,
    ) {
      final render =
          tester.renderObject(
                find
                    .descendant(
                      of: key(canvas),
                      matching: find.byType(CustomPaint),
                    )
                    .first,
              )
              as RenderCustomPaint;
      final rec = TestRecordingCanvas();
      render.painter!.paint(rec, render.size);
      final lines = <(Color, double)>[];
      final circles = <(Offset, double)>[];
      for (final c in rec.invocations) {
        final a = c.invocation.positionalArguments;
        if (c.invocation.memberName == #drawLine) {
          final paint = a[2] as Paint;
          lines.add((paint.color, paint.strokeWidth));
        } else if (c.invocation.memberName == #drawCircle) {
          circles.add((a[0] as Offset, a[1] as double));
        }
      }
      return (lines: lines, circles: circles);
    }

    testWidgets('uses the same overall map, every station still named', (
      tester,
    ) async {
      await pumpApp(tester, location: route);
      expect(key(canvas), findsOneWidget);
      expect(key('overview-viewer'), findsOneWidget);
      expect(key('map-zoom-in'), findsOneWidget);
      final labels = _drawing(tester, canvas: canvas).layout.labels;
      final named = {for (final l in labels) l.stationId};
      // the route's stations and the ones off the route all carry names
      expect(named, containsAll(['alpha', 'beta', 'central', 'yankee']));
      expect(named.length, greaterThan(6));
    });

    testWidgets('ridden segments are thick in the line colour, the rest '
        'faded', (tester) async {
      await pumpApp(tester, location: route);
      final r = painted(tester);
      bool has(Color c, double w) => r.lines.any(
        (l) => l.$1.toARGB32() == c.toARGB32() && l.$2 == w,
      );
      expect(has(const Color(0xFFC62828), 19), isTrue, reason: 'red ridden');
      expect(has(const Color(0xFF1565C0), 19), isTrue, reason: 'blue ridden');
      expect(
        r.lines.any((l) => l.$1.a < 0.5 && l.$2 == 8),
        isTrue,
        reason: 'the rest of the network is faded',
      );
      expect(
        r.lines.any((l) => l.$1.a == 1 && l.$2 == 11),
        isFalse,
        reason: 'nothing is drawn at the normal full-strength width',
      );
    });

    testWidgets('the change station is ringed', (tester) async {
      await pumpApp(tester, location: route);
      final p = _drawing(tester, canvas: canvas).layout.points['central']!;
      expect(
        painted(tester).circles.any((c) => c.$1 == p && c.$2 == 27),
        isTrue,
      );
      expect(key('map-legend-transfer'), findsOneWidget);
      expect(key('map-legend-walk'), findsNothing);
    });

    testWidgets('the screen opens framed on the route, ends ringed', (
      tester,
    ) async {
      await pumpApp(tester, location: route);
      final box = tester.getRect(key('overview-viewer'));
      for (final id in ['alpha', 'beta', 'central', 'yankee']) {
        final p = _onScreen(tester, id, canvas: canvas);
        expect(box.contains(p), isTrue, reason: '$id at $p inside $box');
      }
      final m = _marks(tester);
      expect(m.fromId, 'alpha');
      expect(m.toId, 'yankee');
      expect(m.tags.keys, containsAll(['alpha', 'yankee']));
    });

    testWidgets('tapping a station on the route map opens its detail', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        location: '/go/route/map?from=alpha&to=delta',
      );
      await tester.tapAt(_onScreen(tester, 'beta', canvas: canvas));
      await tester.pumpAndSettle();
      expect(routerOf(c).state.uri.path, '/station/beta');
    });
  });
}
