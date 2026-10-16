import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('Home grid shows a tile for every real feature', (tester) async {
    await pumpApp(tester, location: '/home');
    for (final id in [
      'route',
      'map',
      'lines',
      'nearby',
      'ask',
      'about',
    ]) {
      expect(key('home-tile-$id'), findsOneWidget, reason: id);
    }
    // nothing the dataset cannot back up
    for (final text in ['Ticket price', 'Parking', 'Remove Ads']) {
      expect(find.text(text), findsNothing, reason: text);
    }
  });

  testWidgets('tiles open the matching screens', (tester) async {
    await pumpApp(tester, location: '/home');
    await tester.tap(key('home-tile-route'));
    await tester.pumpAndSettle();
    expect(find.text('Where do you want to go?'), findsOneWidget);

    await pumpApp(tester, location: '/home');
    await tester.tap(key('home-tile-lines'));
    await tester.pumpAndSettle();
    expect(find.text('Metro lines'), findsWidgets);
    expect(find.byType(Card), findsWidgets);
  });

  testWidgets('About names the developer, shows the photo and data counts', (
    tester,
  ) async {
    await pumpApp(tester, location: '/home/about');
    expect(find.text('Agam Singh'), findsOneWidget);
    expect(key('about-photo'), findsOneWidget);
    expect(key('about-stations'), findsOneWidget);
    expect(key('about-lines'), findsOneWidget);
    expect(find.textContaining('not affiliated'), findsOneWidget);
  });

  testWidgets('Hindi interface shows Hindi tile labels', (tester) async {
    await pumpApp(tester, location: '/home', locale: const Locale('hi'));
    expect(find.text('मेट्रो रूट खोजें'), findsOneWidget);
    expect(find.text('परिचय'), findsOneWidget);
  });
}
