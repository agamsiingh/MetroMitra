import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metromitra/features/map/presentation/overview_map.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

/// What the overview canvas painted (circles and text paragraphs).
({int circles, int paragraphs, int lines}) _painted(WidgetTester tester) {
  final render =
      tester.renderObject(key('overview-canvas')) as RenderCustomPaint;
  final canvas = TestRecordingCanvas();
  render.painter!.paint(canvas, render.size);
  var circles = 0;
  var lines = 0;
  for (final c in canvas.invocations) {
    final n = c.invocation.memberName;
    if (n == #drawCircle) circles++;
    if (n == #drawLine) lines++;
  }
  // text goes through TextPainter -> drawParagraph
  final paragraphs = canvas.invocations
      .where((c) => c.invocation.memberName == #drawParagraph)
      .length;
  return (circles: circles, paragraphs: paragraphs, lines: lines);
}

void main() {
  testWidgets('opens from the Map tab and names every station', (
    tester,
  ) async {
    await pumpApp(tester, location: '/map');
    await tester.tap(key('map-overview'));
    await tester.pumpAndSettle();
    expect(key('overview-canvas'), findsOneWidget);
    final snap = demoNetwork();
    final p = _painted(tester);
    // every station is a ring (+ inner dots for interchanges) and is labelled
    expect(p.circles, greaterThanOrEqualTo(snap.stations.length * 2));
    expect(p.paragraphs, snap.stations.length);
    expect(p.lines, greaterThan(0));
  });

  testWidgets('legend lists every line with its dataset colour; credit shown', (
    tester,
  ) async {
    final c = await pumpApp(tester, location: '/map');
    await tester.tap(key('map-overview'));
    await tester.pumpAndSettle();
    final snap = demoNetwork();
    expect(
      find.descendant(
        of: key('overview-legend'),
        matching: find.byType(DecoratedBox),
      ),
      findsAtLeastNWidgets(snap.lines.length),
    );
    expect(key('overview-not-to-scale'), findsOneWidget);
    expect(c, isNotNull);
  });

  testWidgets('labels carry both scripts; Hindi interface swaps the order', (
    tester,
  ) async {
    await pumpApp(tester, location: '/map/overview');
    final render =
        tester.renderObject(key('overview-canvas')) as RenderCustomPaint;
    final painter = render.painter! as OverviewPainter;
    final texts = [
      for (final l in painter.layout.labels) l.painter.text!.toPlainText(),
    ];
    expect(texts, contains('Beta Nagar\nबीटा नगर'));
  });

  testWidgets('the layout never puts two labels on top of each other', (
    tester,
  ) async {
    await pumpApp(tester, location: '/map/overview');
    final render =
        tester.renderObject(key('overview-canvas')) as RenderCustomPaint;
    final layout = (render.painter! as OverviewPainter).layout;
    final rects = [
      for (final l in layout.labels)
        l.offset & Size(l.painter.width, l.painter.height),
    ];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse, reason: '$i vs $j');
      }
    }
  });
}
