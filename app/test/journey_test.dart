import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' as core show Platform;
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/features/journey/application/journey_controller.dart';
import 'package:metromitra/features/journey/presentation/journey_screen.dart';
import 'package:metromitra/shared/data/journey_store.dart';
import 'package:metromitra/shared/location/location_source.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

String _t(WidgetTester tester, String k) =>
    (tester.widget(key(k)) as Text).data ?? '';

/// A clock the test moves forward.
class TestClock {
  DateTime now = monday;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

Future<void> _tap(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

void main() {
  late TestClock clock;
  late MemoryJourneyStore store;
  late FakeKeepAwake awake;
  late List<MethodCall> haptics;

  setUp(() {
    clock = TestClock();
    store = MemoryJourneyStore();
    awake = FakeKeepAwake();
    haptics = [];
  });

  Future<void> open(
    WidgetTester tester,
    String from,
    String to, {
    MetroSnapshot? snapshot,
    Locale? locale,
    LocationSource? location,
    int option = 0,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method.startsWith('HapticFeedback')) haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpApp(
      tester,
      snapshot: snapshot,
      locale: locale,
      clock: clock.call,
      journeyStore: store,
      keepAwake: awake,
      locationSource: location,
      location: '/go/route?from=$from&to=$to',
    );
    if (option > 0) await _tap(tester, 'alt-$option');
    await _tap(tester, 'start-journey');
  }

  Future<void> primary(WidgetTester tester) => _tap(tester, 'journey-primary');

  Future<void> tick(WidgetTester tester, Duration d) async {
    clock.advance(d);
    await tester.pump(journeyTick);
    await tester.pumpAndSettle();
  }

  group('start and steps', () {
    testWidgets('Start journey opens the first step; data gaps are said', (
      tester,
    ) async {
      await open(tester, 'alpha', 'delta');
      expect(key('journey'), findsOneWidget);
      expect(_t(tester, 'journey-step-count'), 'Step 1 of 4');
      expect(_t(tester, 'step-title'), 'Go into Alpha Chowk');
      expect(_t(tester, 'gates-unknown'), 'Gate information unavailable.');
      expect(find.text("I'm inside the station"), findsOneWidget);
      expect(_t(tester, 'next-step'), startsWith('Next: Board Test Red Line'));
      expect(key('journey-estimate-note'), findsOneWidget);
      expect(key('data-banner'), findsOneWidget);
    });

    testWidgets('one ride: enter, board, ride with stops, exit, done', (
      tester,
    ) async {
      await open(tester, 'alpha', 'delta');
      await primary(tester);
      expect(
        _t(tester, 'step-title'),
        'Board Test Red Line towards Twin Place',
      );
      expect(_t(tester, 'platform'), 'Platform information unavailable.');
      await primary(tester);
      expect(_t(tester, 'step-title'), 'Get off at Delta Vihar');
      expect(_t(tester, 'stops-left'), '3 stops to go');
      expect(_t(tester, 'near'), 'Now around Alpha Chowk (estimated)');

      await tick(tester, const Duration(seconds: 100));
      expect(_t(tester, 'stops-left'), '2 stops to go');
      expect(_t(tester, 'near'), 'Now around Beta Nagar (estimated)');
      expect(haptics, isEmpty);

      await tick(tester, const Duration(seconds: 100));
      expect(_t(tester, 'stops-left'), '1 stop to go');
      expect(key('get-off-next'), findsOneWidget);
      expect(haptics, hasLength(1), reason: 'one vibration for the alert');
      await tick(tester, const Duration(seconds: 5));
      expect(haptics, hasLength(1), reason: 'not repeated every tick');

      await tick(tester, const Duration(seconds: 100));
      expect(_t(tester, 'should-be-there'), contains('Delta Vihar'));

      // hours later the app still waits for the rider to confirm
      await tick(tester, const Duration(hours: 3));
      expect(_t(tester, 'step-title'), 'Get off at Delta Vihar');

      await primary(tester);
      expect(_t(tester, 'step-title'), 'Leave Delta Vihar');
      expect(_t(tester, 'gates-unknown'), 'Exit information unavailable.');
      expect(key('no-best-exit'), findsOneWidget);
      expect(key('next-step'), findsNothing);
      expect(find.text('Done'), findsOneWidget);

      await primary(tester);
      expect(key('journey'), findsNothing);
      expect(find.text('Where do you want to go?'), findsOneWidget);
      expect(store.saved, isNull, reason: 'finished journeys are cleared');
      expect(awake.isOn, isFalse);
    });

    testWidgets('a change: change card with the walk the data gives', (
      tester,
    ) async {
      await open(tester, 'alpha', 'yankee');
      for (var i = 0; i < 3; i++) {
        await primary(tester);
      }
      expect(_t(tester, 'step-title'), 'Change at Central Place');
      expect(_t(tester, 'change-walk'), 'Walk about 2 min (90 m)');
      expect(find.text("I've changed"), findsOneWidget);
      await primary(tester);
      expect(_t(tester, 'step-title'), startsWith('Board Test Blue Line'));
    });

    testWidgets('an out-of-system walk is a step with its consequences', (
      tester,
    ) async {
      await open(tester, 'alpha', 'gamut');
      var guard = 0;
      while (!_t(tester, 'step-title').startsWith('Walk to') && guard++ < 8) {
        await primary(tester);
      }
      expect(_t(tester, 'step-title'), 'Walk to Gamma Colony');
      expect(
        find.text('You leave the station area. You will need a new ticket.'),
        findsOneWidget,
      );
      expect(find.text("I've arrived"), findsOneWidget);
    });

    testWidgets('the line splits: the forced change is explained', (
      tester,
    ) async {
      await open(tester, 'ringa', 'spur');
      var guard = 0;
      while (!_t(tester, 'step-title').startsWith('Change at') && guard++ < 8) {
        await primary(tester);
      }
      expect(_t(tester, 'step-title'), 'Change at Hub Junction');
      expect(
        find.text('The line splits here. Get off and board the next train.'),
        findsOneWidget,
      );
    });

    testWidgets('Hindi interface', (tester) async {
      await open(tester, 'alpha', 'delta', locale: const Locale('hi'));
      expect(_t(tester, 'step-title'), 'अल्फा चौक स्टेशन में जाएँ');
      expect(find.text('मैं स्टेशन के अंदर हूँ'), findsOneWidget);
    });
  });

  group('platforms and gates come only from the data', () {
    MetroSnapshot withFacts(Confidence confidence) => demoNetwork().copyWith(
      platforms: [
        core.Platform(
          stationId: 'alpha',
          lineId: 'red',
          number: '2',
          towardsStationId: 'twin-1',
          provenance: Provenance(
            sourceId: 'test-fixture',
            confidence: confidence,
            verifiedOn: confidence == Confidence.verified ? '2026-09-01' : null,
          ),
        ),
      ],
      gates: const [
        Gate(
          id: 'delta:g1',
          stationId: 'delta',
          number: 1,
          nameEn: 'North',
          hasLift: true,
          provenance: testProvenance,
        ),
        Gate(
          id: 'delta:g2',
          stationId: 'delta',
          number: 2,
          isOpen: false,
          provenance: testProvenance,
        ),
      ],
      gateLandmarks: const [
        GateLandmark(
          gateId: 'delta:g1',
          textEn: 'Test Market',
          kind: GateLandmarkKind.landmark,
        ),
      ],
    );

    testWidgets('a verified platform is shown plainly', (tester) async {
      await open(
        tester,
        'alpha',
        'delta',
        snapshot: withFacts(Confidence.verified),
      );
      await primary(tester);
      expect(_t(tester, 'platform'), 'Platform 2');
    });

    testWidgets('an unverified platform says so', (tester) async {
      await open(
        tester,
        'alpha',
        'delta',
        snapshot: withFacts(Confidence.community),
      );
      await primary(tester);
      expect(_t(tester, 'platform'), 'Platform 2 (unverified)');
    });

    testWidgets('exit gates: open ones with landmarks; closed left out; '
        'no best exit is claimed', (tester) async {
      await open(
        tester,
        'alpha',
        'delta',
        snapshot: withFacts(Confidence.verified),
      );
      for (var i = 0; i < 3; i++) {
        await primary(tester);
      }
      expect(_t(tester, 'step-title'), 'Leave Delta Vihar');
      expect(
        _t(tester, 'gate-delta:g1'),
        'Gate 1 · North · lift · Test Market',
      );
      expect(key('gate-delta:g2'), findsNothing);
      expect(key('gates-unknown'), findsNothing);
      expect(key('no-best-exit'), findsOneWidget);
    });
  });

  group('corrections', () {
    testWidgets('"I\'m at…" lists route stations and moves the estimate', (
      tester,
    ) async {
      await open(tester, 'alpha', 'delta');
      await _tap(tester, 'journey-correct');
      for (final id in ['alpha', 'beta', 'central', 'delta']) {
        expect(key('correct-$id'), findsOneWidget);
      }
      expect(key('correct-yankee'), findsNothing);
      await _tap(tester, 'correct-central');
      expect(_t(tester, 'step-title'), 'Get off at Delta Vihar');
      expect(_t(tester, 'stops-left'), '1 stop to go');
      expect(key('get-off-next'), findsOneWidget);
      // the estimate now runs from central
      await tick(tester, const Duration(seconds: 100));
      expect(key('should-be-there'), findsOneWidget);
    });

    testWidgets('location: snapped to a route station within 250 m', (
      tester,
    ) async {
      final source = FakeLocationSource(
        // 0.0005 deg (~55 m) from central (index 2 in the invented list)
        const LocationFix(lat: 28.5025, lng: 77.1),
      );
      await open(tester, 'alpha', 'delta', location: source);
      await _tap(tester, 'journey-locate');
      expect(source.calls, 1);
      expect(find.text('Moved to Central Place'), findsOneWidget);
      expect(_t(tester, 'stops-left'), '1 stop to go');
      // nothing about the position is saved
      expect(store.saved, isNot(contains('28.50')));
    });

    testWidgets('location far from the route: nothing moves', (tester) async {
      await open(
        tester,
        'alpha',
        'delta',
        location: FakeLocationSource(const LocationFix(lat: 19, lng: 72.8)),
      );
      await _tap(tester, 'journey-locate');
      expect(
        find.text('No station of this route within 250 m of you.'),
        findsOneWidget,
      );
      expect(_t(tester, 'step-title'), 'Go into Alpha Chowk');
    });

    for (final (name, result, text) in [
      (
        'denied',
        const LocationDenied() as LocationResult,
        'Location is not allowed.',
      ),
      ('unavailable', const LocationUnavailable(), "Can't get your location"),
      ('invalid', const LocationFix(lat: 0, lng: 0), "Can't get your location"),
    ]) {
      testWidgets('location $name: explained, journey unchanged', (
        tester,
      ) async {
        await open(
          tester,
          'alpha',
          'delta',
          location: FakeLocationSource(result),
        );
        await _tap(tester, 'journey-locate');
        expect(find.textContaining(text), findsOneWidget);
        expect(_t(tester, 'step-title'), 'Go into Alpha Chowk');
      });
    }

    testWidgets('while a fix is pending the button says so and is disabled '
        '(found on a device: a fix can take seconds)', (tester) async {
      final pending = Completer<LocationResult>();
      final source = _PendingLocation(pending.future);
      await open(tester, 'alpha', 'delta', location: source);
      await tester.ensureVisible(key('journey-locate'));
      await tester.tap(key('journey-locate'));
      await tester.pump();
      expect(find.text('Finding your location…'), findsOneWidget);
      await tester.tap(key('journey-locate'), warnIfMissed: false);
      await tester.pump();
      expect(source.calls, 1, reason: 'no second request while waiting');
      pending.complete(const LocationFix(lat: 28.5025, lng: 77.1));
      await tester.pumpAndSettle();
      expect(find.text('Use my location'), findsOneWidget);
      expect(find.text('Moved to Central Place'), findsOneWidget);
    });

    testWidgets('location is never asked for without a tap', (tester) async {
      final source = FakeLocationSource(
        const LocationFix(lat: 28.5, lng: 77.1),
      );
      await open(tester, 'alpha', 'delta', location: source);
      await primary(tester);
      await primary(tester);
      await tick(tester, const Duration(minutes: 5));
      expect(source.calls, 0);
    });
  });

  group('keep awake, back and end', () {
    testWidgets('the screen stays on by default; the switch turns it off', (
      tester,
    ) async {
      await open(tester, 'alpha', 'delta');
      expect(awake.isOn, isTrue);
      await _tap(tester, 'keep-awake');
      expect(awake.isOn, isFalse);
      expect((jsonDecode(store.saved!) as Map)['keepAwake'], isFalse);
      await _tap(tester, 'keep-awake');
      expect(awake.isOn, isTrue);
    });

    testWidgets('back asks "End journey?"; keep going stays', (tester) async {
      await open(tester, 'alpha', 'delta');
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(key('end-journey-dialog'), findsOneWidget);
      await _tap(tester, 'end-cancel');
      expect(key('journey'), findsOneWidget);
      expect(store.saved, isNotNull);
    });

    testWidgets('ending clears the journey and the screen lock', (
      tester,
    ) async {
      await open(tester, 'alpha', 'delta');
      await _tap(tester, 'journey-close');
      await _tap(tester, 'end-confirm');
      expect(key('journey'), findsNothing);
      expect(store.saved, isNull);
      expect(awake.isOn, isFalse);
      expect(key('journey-banner'), findsNothing);
    });

    testWidgets('leaving with the system back keeps nothing half-done', (
      tester,
    ) async {
      final c = await pumpApp(tester, journeyStore: store, keepAwake: awake);
      routerOf(c).go('/journey');
      await tester.pumpAndSettle();
      expect(key('journey-none'), findsOneWidget);
      expect(awake.isOn, isFalse);
    });

    testWidgets('a failing save never stops the journey', (tester) async {
      store.failSaves = true;
      await open(tester, 'alpha', 'delta');
      await primary(tester);
      expect(_t(tester, 'step-title'), startsWith('Board'));
    });
  });

  group('resume after the app is killed', () {
    testWidgets('a saved journey comes back at the same step', (
      tester,
    ) async {
      await open(tester, 'alpha', 'delta');
      await primary(tester);
      await primary(tester); // on the train
      final saved = store.saved!;
      final json = jsonDecode(saved) as Map<String, Object?>;
      expect(json.keys.toSet(), {
        'v',
        'dataset',
        'from',
        'to',
        'opt',
        'signature',
        'state',
        'keepAwake',
      });
      expect(saved, isNot(contains('lat')));

      // "process death": a fresh app with the same user database
      clock.advance(const Duration(seconds: 150));
      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        clock: clock.call,
        journeyStore: store,
        keepAwake: awake,
      );
      expect(key('journey-banner'), findsOneWidget);
      expect(
        find.text('Journey in progress: Alpha Chowk to Delta Vihar'),
        findsOneWidget,
      );
      await _tap(tester, 'resume-journey');
      expect(_t(tester, 'step-title'), 'Get off at Delta Vihar');
      // the ride estimate kept running while the app was gone
      expect(_t(tester, 'stops-left'), '2 stops to go');
    });

    testWidgets('End from the Home banner clears it', (tester) async {
      await open(tester, 'alpha', 'delta');
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, clock: clock.call, journeyStore: store);
      await _tap(tester, 'resume-end');
      expect(key('journey-banner'), findsNothing);
      expect(store.saved, isNull);
    });

    Future<void> restoreFrom(WidgetTester tester, String raw) async {
      store.saved = raw;
      await pumpApp(tester, clock: clock.call, journeyStore: store);
    }

    Map<String, Object?> savedJourney() => {
      'v': 1,
      'dataset': '2026.10.0',
      'from': 'alpha',
      'to': 'delta',
      'opt': 0,
      'signature': RoutePlanner(
        demoNetwork(),
      ).plan('alpha', 'delta').itineraries.first.signature,
      'state': JourneyState.start(monday.millisecondsSinceEpoch).toJson(),
      'keepAwake': true,
    };

    testWidgets('a valid saved journey is restored', (tester) async {
      await restoreFrom(tester, jsonEncode(savedJourney()));
      expect(key('journey-banner'), findsOneWidget);
    });

    final broken =
        <String, Map<String, Object?> Function(Map<String, Object?>)>{
          'other dataset version': (j) => {...j, 'dataset': '2099.1.1'},
          'route changed': (j) => {...j, 'signature': 'R:x'},
          'unknown station': (j) => {...j, 'to': 'nope'},
          'option out of range': (j) => {...j, 'opt': 7},
          'bad state': (j) => {...j, 'state': 'x'},
          'unknown format version': (j) => {...j, 'v': 2},
        };
    for (final e in broken.entries) {
      testWidgets('not restored: ${e.key}; cleared and explained', (
        tester,
      ) async {
        await restoreFrom(tester, jsonEncode(e.value(savedJourney())));
        expect(key('journey-banner'), findsNothing);
        expect(key('journey-not-restored'), findsOneWidget);
        expect(find.textContaining('metro data changed'), findsOneWidget);
        expect(store.saved, isNull);
        await _tap(tester, 'journey-dismiss');
        expect(key('journey-not-restored'), findsNothing);
      });
    }

    testWidgets('not restored: not JSON at all', (tester) async {
      await restoreFrom(tester, '{oops');
      expect(key('journey-not-restored'), findsOneWidget);
      expect(store.saved, isNull);
    });

    testWidgets('not restored: too old', (tester) async {
      clock.advance(journeyMaxAge + const Duration(minutes: 1));
      await restoreFrom(tester, jsonEncode(savedJourney()));
      expect(find.textContaining('too old'), findsOneWidget);
      expect(store.saved, isNull);
    });

    testWidgets('nothing saved: no banner, nothing shown', (tester) async {
      await pumpApp(tester, clock: clock.call, journeyStore: store);
      expect(key('journey-banner'), findsNothing);
      expect(key('journey-not-restored'), findsNothing);
    });
  });

  group('user database file (journey_state)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('journey_store_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('save, load, overwrite, clear: one row', () async {
      final s = SqliteJourneyStore(() async => dir);
      expect(await s.load(), isNull);
      await s.save('{"a":1}', 1);
      expect(await s.load(), '{"a":1}');
      await s.save('{"a":2}', 2);
      expect(await s.load(), '{"a":2}');
      await s.clear();
      expect(await s.load(), isNull);
    });

    test('survives a "restart" (a new store on the same file)', () async {
      await SqliteJourneyStore(() async => dir).save('{"k":true}', 1);
      expect(await SqliteJourneyStore(() async => dir).load(), '{"k":true}');
    });

    test('a damaged file reads as "nothing saved"', () async {
      File('${dir.path}/${SqliteJourneyStore.fileName}').writeAsBytesSync(
        List.generate(512, (i) => i % 251),
      );
      expect(await SqliteJourneyStore(() async => dir).load(), isNull);
    });
  });
}

class _PendingLocation implements LocationSource {
  _PendingLocation(this.result);

  final Future<LocationResult> result;
  int calls = 0;

  @override
  Future<LocationResult> current() {
    calls++;
    return result;
  }

  @override
  Stream<LocationResult> watch() => const Stream.empty();

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> openLocationSettings() async {}
}
