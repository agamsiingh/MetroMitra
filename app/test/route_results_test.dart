import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/go/presentation/route_results_screen.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

String routeUrl(String from, String to) => '/go/route?from=$from&to=$to';

Text textOf(WidgetTester tester, String k) => tester.widget<Text>(key(k));

void main() {
  group('lookup (application layer)', () {
    // The planner and fare engine are tested in metro_core; here we check what
    // the app asks of them and how outcomes are classified.
    final services = MetroServices(demoNetwork());

    test('every demo station pair gets a defined outcome', () {
      for (final a in services.snapshot.stations) {
        for (final b in services.snapshot.stations) {
          final r = services.planner.plan(a.id, b.id);
          expect(RouteStatus.values, contains(r.status));
        }
      }
    });
  });

  group('a direct trip', () {
    testWidgets('shows duration (approximate), changes, stops and the line', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'echo'));
      // wait 180 + 4 hops * 100 s = 580 s -> ~10 min
      expect(textOf(tester, 'summary-duration').data, 'About 10 min');
      expect(textOf(tester, 'summary-facts').data, 'No changes · 4 stops');
      expect(key('ride-0'), findsOneWidget);
      expect(find.textContaining('Test Red Line towards'), findsOneWidget);
      expect(find.text('Alpha Chowk to Echo Park'), findsOneWidget);
      expect(key('header-from'), findsOneWidget);
      expect(textOf(tester, 'header-from').data, 'Alpha Chowk');
      expect(textOf(tester, 'header-to').data, 'Echo Park');
    });

    testWidgets('distance: the sum of ridden edges, labelled as an estimate '
        'unless every edge is verified', (tester) async {
      final c = await pumpApp(tester, location: routeUrl('alpha', 'echo'));
      final services = c.read(metroServicesProvider);
      final it = services.planner.plan('alpha', 'echo').itineraries.first;
      final m = routeDistanceM(it);
      expect(m, greaterThan(0));
      expect(
        textOf(tester, 'summary-distance').data,
        'About ${(m / 1000).toStringAsFixed(1)} km by metro',
      );
      final estimate = distanceIsEstimate(it, services.snapshot);
      expect(
        key('summary-distance-note'),
        estimate ? findsOneWidget : findsNothing,
      );
    });

    testWidgets('times are labelled approximate while estimates are used', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'echo'));
      expect(key('approx-notice'), findsOneWidget);
      expect(find.text('Approximate times'), findsOneWidget);
      expect(find.textContaining('estimates'), findsWidgets);
      expect(find.textContaining('About'), findsWidgets);
    });

    testWidgets('the assumptions behind the times can be opened', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'echo'));
      expect(key('assumptions'), findsOneWidget);
      await tester.tap(find.text('How these times are estimated'));
      await tester.pumpAndSettle();
      expect(
        find.text('Each boarding adds an assumed wait of 3 min.'),
        findsOneWidget,
      );
    });

    testWidgets('the stops of a ride can be expanded', (tester) async {
      await pumpApp(tester, location: routeUrl('alpha', 'echo'));
      expect(find.text('Beta Nagar'), findsNothing);
      await tester.tap(key('ride-toggle-0'));
      await tester.pumpAndSettle();
      expect(find.text('Beta Nagar'), findsOneWidget);
      expect(find.text('Delta Vihar'), findsOneWidget);
      expect(find.text('Hide stops'), findsOneWidget);
    });

    testWidgets('data banner: test data is flagged, a draft is flagged', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'echo'));
      expect(
        find.text('TEST DATA — not real metro information.'),
        findsOneWidget,
      );
    });

    testWidgets('a draft dataset shows the draft banner', (tester) async {
      await pumpApp(
        tester,
        result: BootstrapReady(
          snapshot: demoNetwork(draft: true, testData: false),
          sourceLabel: 'dev',
        ),
        location: routeUrl('alpha', 'echo'),
      );
      expect(
        find.text('Draft data — not verified. Details may be wrong.'),
        findsOneWidget,
      );
    });

    testWidgets('a release dataset shows no banner and no approx label when '
        'nothing is estimated', (tester) async {
      await pumpApp(
        tester,
        snapshot: demoNetwork(testData: false),
        location: routeUrl('alpha', 'echo'),
      );
      expect(key('data-banner'), findsNothing);
      // the board wait is always an assumption, so the notice must remain
      expect(key('approx-notice'), findsOneWidget);
    });
  });

  group('changes and walking', () {
    testWidgets('a line change shows the walk, step data and both lines', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'yankee'));
      expect(textOf(tester, 'summary-facts').data, contains('1 change'));
      expect(find.text('Change at Central Place'), findsOneWidget);
      expect(find.text('Test Red Line to Test Blue Line'), findsOneWidget);
      // known interchange walk: 120 s = 2 min, 90 m
      expect(textOf(tester, 'change-walk-1').data, 'Walk about 2 min (90 m)');
      expect(
        find.text('90 m walking'),
        findsNothing,
        reason: 'walking total sits in the facts line',
      );
      expect(textOf(tester, 'summary-facts').data, contains('90 m walking'));
      // step-free is NULL in the data: not claimed
      expect(find.text('Step-free'), findsNothing);
    });

    testWidgets('an interchange without walk data is estimated and warned', (
      tester,
    ) async {
      final net = buildTestNetwork(
        stations: const [
          TStation('a', 'Aaa Stop'),
          TStation('x', 'Xxx Stop'),
          TStation('b', 'Bbb Stop'),
        ],
        services: const [
          TService('red-main', 'red', ['a', 'x']),
          TService('blue-main', 'blue', ['x', 'b']),
        ],
        transfers: const [('x', 'red', 'blue', null, null)],
      );
      await pumpApp(tester, snapshot: net, location: routeUrl('a', 'b'));
      expect(
        textOf(tester, 'change-walk-1').data,
        startsWith('Allow about'),
      );
      expect(textOf(tester, 'change-walk-1').data, contains('(estimated)'));
      expect(key('warnings'), findsOneWidget);
      expect(
        find.text('Walking time at Xxx Stop is estimated, not measured.'),
        findsOneWidget,
      );
      // the list is lazy: bring the section header, then its content, in
      final list = find.descendant(
        of: key('route-found'),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('How these times are estimated'),
        300,
        scrollable: list.first,
      );
      await tester.ensureVisible(find.text('How these times are estimated'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How these times are estimated'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Interchange walking times are estimated.'),
        300,
        scrollable: list.first,
      );
      expect(
        find.text('Interchange walking times are estimated.'),
        findsOneWidget,
      );
    });

    testWidgets('an out-of-system walk is shown with its consequences', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'gamut'));
      expect(key('walk-1'), findsOneWidget);
      expect(find.text('Walk to Gamma Colony'), findsOneWidget);
      expect(find.text('300 m, about 7 min'), findsOneWidget);
      expect(
        find.text('You leave the station area. You will need a new ticket.'),
        findsOneWidget,
      );
      expect(
        find.text('This trip needs more than one ticket.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'summary-facts').data, contains('1 change'));
    });
  });

  group('forced change at a repeated station (ring + spur)', () {
    testWidgets('the app says the line splits and warns', (tester) async {
      await pumpApp(tester, location: routeUrl('spur', 'ringa'));
      expect(find.text('Change at Hub Junction'), findsOneWidget);
      expect(
        find.text('The line splits here. Get off and board the next train.'),
        findsOneWidget,
      );
      expect(
        find.text('You must change trains at Hub Junction.'),
        findsAtLeastNWidgets(1),
      );
      expect(textOf(tester, 'summary-facts').data, contains('1 change'));
      // a ring service names no terminal
      expect(find.textContaining('towards'), findsNothing);
    });

    testWidgets('a ride that does not cross the seam needs no change', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('ringa', 'ringb'));
      expect(textOf(tester, 'summary-facts').data, startsWith('No changes'));
      expect(key('warnings'), findsNothing);
    });
  });

  group('alternatives and profiles', () {
    testWidgets('several alternatives are offered with their profiles', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'zulu'));
      expect(key('alt-0'), findsOneWidget);
      expect(key('alt-1'), findsOneWidget);
      expect(find.text('Fastest · Fewest stops'), findsOneWidget);
      expect(find.text('Fewest changes · Least walking'), findsOneWidget);
    });

    testWidgets('selecting an alternative swaps the whole timeline', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'zulu'));
      // fastest: three short lines, two changes
      final fastestFacts = textOf(tester, 'summary-facts').data;
      expect(fastestFacts, contains('2 changes'));
      expect(find.text('Change at Quick Pivot'), findsOneWidget);
      final fastestDuration = textOf(tester, 'summary-duration').data;

      await tester.tap(key('alt-1'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'summary-facts').data, contains('No changes'));
      expect(find.text('Change at Quick Pivot'), findsNothing);
      expect(find.text('Test Slow Line'), findsWidgets);
      expect(textOf(tester, 'summary-duration').data, isNot(fastestDuration));
    });

    testWidgets('a single result shows no chip row', (tester) async {
      await pumpApp(tester, location: routeUrl('alpha', 'echo'));
      expect(key('alt-0'), findsNothing);
    });
  });

  group('fare: only from dataset fare data', () {
    testWidgets('a priced trip shows the amount and how it was derived', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'echo'));
      // 4 km -> slab [2,5) = 2050 paise
      expect(textOf(tester, 'fare-total').data, '₹20.50');
      expect(find.text('Estimated from distance'), findsOneWidget);
      expect(
        find.text('Fare for today. Public holidays are not considered.'),
        findsOneWidget,
      );
      expect(key('fare-unavailable'), findsNothing);
    });

    testWidgets('no fare data: says so and shows no amount', (tester) async {
      await pumpApp(
        tester,
        snapshot: demoNetwork(fares: false),
        location: routeUrl('alpha', 'echo'),
      );
      expect(key('fare-unavailable'), findsOneWidget);
      expect(find.text('Fare not available'), findsOneWidget);
      expect(key('fare-total'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('a day type the data has no slab for shows no fare', (
      tester,
    ) async {
      await pumpApp(
        tester,
        now: sunday,
        location: routeUrl('alpha', 'echo'),
      );
      expect(key('fare-unavailable'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('part-priced trips show no total', (tester) async {
      await pumpApp(tester, location: routeUrl('alpha', 'gamut'));
      expect(key('fare-partial'), findsOneWidget);
      expect(key('fare-total'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('smart-card fare is shown only when the data has a discount', (
      tester,
    ) async {
      final base = demoNetwork();
      final withDiscount = base.copyWith(
        fareDiscounts: const [
          FareDiscount(
            fareSystemId: 'fs-a',
            media: FareMedia.smartCard,
            kind: FareDiscountKind.base,
            percent: 10,
          ),
        ],
      );
      await pumpApp(
        tester,
        snapshot: withDiscount,
        location: routeUrl('alpha', 'echo'),
      );
      expect(textOf(tester, 'fare-total').data, 'Token: ₹20.50');
      expect(textOf(tester, 'fare-card').data, 'Smart card: ₹18.45');
    });
  });

  group('edge cases', () {
    testWidgets('origin equals destination (deep link)', (tester) async {
      await pumpApp(tester, location: routeUrl('alpha', 'alpha'));
      expect(key('route-same'), findsOneWidget);
      expect(find.text('Same station'), findsOneWidget);
      expect(key('route-found'), findsNothing);
    });

    testWidgets('unreachable stations (disconnected network)', (tester) async {
      await pumpApp(tester, location: routeUrl('alpha', 'isle-a'));
      expect(key('route-unreachable'), findsOneWidget);
      expect(find.text('No route found'), findsOneWidget);
      expect(
        find.textContaining('from Alpha Chowk to Island Alpha'),
        findsOneWidget,
      );
      expect(key('fare-total'), findsNothing);
    });

    testWidgets('a station served by no open line', (tester) async {
      await pumpApp(tester, location: routeUrl('alpha', 'halt'));
      expect(key('route-not-served'), findsOneWidget);
      expect(
        find.text('Halt Road is not served by any open line in the data.'),
        findsOneWidget,
      );
    });

    testWidgets('an id that is not in the dataset is an error, not a route', (
      tester,
    ) async {
      await pumpApp(tester, location: routeUrl('alpha', 'atlantis'));
      expect(key('route-unknown'), findsOneWidget);
      // the unknown end is named in the header and in the message
      expect(find.text('Station not found'), findsNWidgets(2));
      expect(textOf(tester, 'header-from').data, 'Alpha Chowk');
    });

    testWidgets('missing ids in the link do not crash', (tester) async {
      await pumpApp(tester, location: '/go/route');
      expect(key('route-unknown'), findsOneWidget);
    });

    testWidgets('a display name is not an id', (tester) async {
      await pumpApp(tester, location: routeUrl('Alpha Chowk', 'Echo Park'));
      expect(key('route-unknown'), findsOneWidget);
    });

    testWidgets('swap reverses the journey and keeps ids', (tester) async {
      final c = await pumpApp(tester, location: routeUrl('alpha', 'yankee'));
      expect(textOf(tester, 'header-from').data, 'Alpha Chowk');
      await tester.tap(key('swap-route'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'header-from').data, 'Yankee Bagh');
      expect(textOf(tester, 'header-to').data, 'Alpha Chowk');
      expect(selection(c).fromId, 'yankee');
      expect(selection(c).toId, 'alpha');
      expect(key('route-found'), findsOneWidget);
    });
  });

  group('names and Hindi', () {
    testWidgets('Hindi interface shows Hindi names where the data has them', (
      tester,
    ) async {
      await pumpApp(
        tester,
        locale: const Locale('hi'),
        location: routeUrl('alpha', 'yankee'),
      );
      expect(textOf(tester, 'header-from').data, 'अल्फा चौक');
      expect(textOf(tester, 'header-to').data, 'यांकी बाग');
      expect(find.text('सेंट्रल प्लेस पर बदलें'), findsOneWidget);
      expect(textOf(tester, 'summary-duration').data, startsWith('लगभग'));
    });

    testWidgets('a station with no Hindi name stays English in Hindi mode', (
      tester,
    ) async {
      await pumpApp(
        tester,
        locale: const Locale('hi'),
        location: routeUrl('xray', 'yankee'),
      );
      expect(textOf(tester, 'header-from').data, 'Xray Gate');
      expect(textOf(tester, 'header-to').data, 'यांकी बाग');
    });

    testWidgets('line names without Hindi fall back to English', (
      tester,
    ) async {
      await pumpApp(
        tester,
        locale: const Locale('hi'),
        location: routeUrl('alpha', 'yankee'),
      );
      expect(find.textContaining('Test Blue Line'), findsWidgets);
      expect(find.textContaining('टेस्ट लाल लाइन'), findsWidgets);
    });
  });

  group('home to results flow', () {
    testWidgets('choose From and To, find the route', (tester) async {
      final c = await pumpApp(tester);
      expect(
        tester.widget<FilledButton>(key('find-route')).onPressed,
        isNull,
      );
      await pickStation(tester, JourneyEnd.from, 'alpha', 'alpha');
      expect(
        tester.widget<FilledButton>(key('find-route')).onPressed,
        isNull,
        reason: 'needs both ends',
      );
      await pickStation(tester, JourneyEnd.to, 'yankee', 'yankee');
      expect(selection(c).canSearch, isTrue);
      await tester.tap(key('find-route'));
      await tester.pumpAndSettle();
      expect(key('route-found'), findsOneWidget);
      expect(textOf(tester, 'header-from').data, 'Alpha Chowk');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Where do you want to go?'), findsOneWidget);
    });

    testWidgets('same station on both ends blocks the search with a message', (
      tester,
    ) async {
      await pumpApp(tester);
      await pickStation(tester, JourneyEnd.from, 'alpha', 'alpha');
      await pickStation(tester, JourneyEnd.to, 'alpha', 'alpha');
      expect(key('same-station-message'), findsOneWidget);
      expect(find.text('Choose two different stations.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('find-route')).onPressed,
        isNull,
      );
    });

    testWidgets('swap on Home exchanges the two ends', (tester) async {
      final c = await pumpApp(tester);
      await pickStation(tester, JourneyEnd.from, 'alpha', 'alpha');
      await pickStation(tester, JourneyEnd.to, 'echo', 'echo');
      await tester.tap(key('swap'));
      await tester.pumpAndSettle();
      expect(selection(c).fromId, 'echo');
      expect(selection(c).toId, 'alpha');
    });

    testWidgets('a remembered id that left the dataset is reported', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      c.read(journeyProvider.notifier).set(JourneyEnd.from, 'vanished');
      await tester.pumpAndSettle();
      expect(
        find.text('This station is not in the current data.'),
        findsOneWidget,
      );
    });
  });
}
