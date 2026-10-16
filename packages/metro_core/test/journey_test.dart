import 'dart:convert';
import 'dart:io';

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/net_builder.dart';

Itinerary best(MetroSnapshot s, String a, String b) {
  final r = RoutePlanner(s).plan(a, b);
  if (r.status != RouteStatus.ok) throw StateError('no route $a -> $b');
  return r.itineraries.first;
}

List<String> kinds(JourneyPlan p) => [for (final s in p.steps) s.kind.name];

/// Invented: red a-b-c-d (100 s hops), blue x-c-y, walk d -> w (exit),
/// green w-z.
MetroSnapshot net({
  List<Platform> platforms = const [],
  List<Gate> gates = const [],
  List<GateLandmark> landmarks = const [],
}) {
  final s = buildNet(
    const [
      Svc('red', ['a', 'b', 'c', 'd']),
      Svc('blue', ['x', 'c', 'y']),
      Svc('green', ['w', 'z']),
    ],
    transfers: const [
      Xfer('c', 'red', 'blue', walkS: 60, walkM: 50),
      Xfer('c', 'blue', 'red', walkS: 60, walkM: 50),
    ],
    walks: const [
      Walk('w1', 'd', 'w', 300, 250, exit: true),
      Walk('w2', 'w', 'd', 300, 250, exit: true),
    ],
  );
  return s.copyWith(
    platforms: platforms,
    gates: gates,
    gateLandmarks: landmarks,
  );
}

const t0 = 1700000000000;

void main() {
  group('plan', () {
    test('one ride: enter, board, ride, exit', () {
      final p = JourneyPlan.fromItinerary(net(), best(net(), 'a', 'c'));
      expect(kinds(p), ['enter', 'board', 'ride', 'exit']);
      expect(p.fromId, 'a');
      expect(p.toId, 'c');
      final ride = p.steps[2];
      expect(ride.stationIds, ['a', 'b', 'c']);
      expect(ride.stopCount, 2);
      expect(ride.toStationId, 'c');
      expect(ride.towardsStationId, 'd');
      expect(p.steps[1].towardsStationId, 'd');
    });

    test('a change: ride, change, board, ride', () {
      final p = JourneyPlan.fromItinerary(net(), best(net(), 'a', 'y'));
      expect(kinds(p), [
        'enter',
        'board',
        'ride',
        'change',
        'board',
        'ride',
        'exit',
      ]);
      final change = p.steps[3];
      expect(change.stationId, 'c');
      expect((change.lineId, change.toLineId), ('red', 'blue'));
      expect((change.walkM, change.walkS), (50, 60));
      expect(change.walkEstimated, isFalse);
      expect(change.transferKind, TransferKind.lineChange);
    });

    test('an out-of-system walk is a step of its own', () {
      final p = JourneyPlan.fromItinerary(net(), best(net(), 'a', 'z'));
      expect(kinds(p), [
        'enter',
        'board',
        'ride',
        'walk',
        'board',
        'ride',
        'exit',
      ]);
      final walk = p.steps[3];
      expect((walk.stationId, walk.toStationId), ('d', 'w'));
      expect((walk.walkM, walk.walkS), (250, 300));
      expect(walk.requiresExit, isTrue);
    });

    test('through-running: stay on board, no second boarding', () {
      final s = buildNet(const [
        Svc('t1', ['a', 'b', 'c'], line: 'l1', through: 't2'),
        Svc('t2', ['c', 'd', 'e'], line: 'l2'),
      ]);
      final p = JourneyPlan.fromItinerary(s, best(s, 'a', 'e'));
      expect(kinds(p), [
        'enter',
        'board',
        'ride',
        'stayOnBoard',
        'ride',
        'exit',
      ]);
      expect((p.steps[3].lineId, p.steps[3].toLineId), ('l1', 'l2'));
    });

    test('no platform or gate data: unknown, never guessed', () {
      final p = JourneyPlan.fromItinerary(net(), best(net(), 'a', 'y'));
      for (final st in p.steps) {
        expect(st.platform, isNull);
        expect(st.gates, isEmpty);
      }
    });

    test('platform only from a matching row (service or direction)', () {
      final s = net(
        platforms: const [
          // matches by direction
          Platform(
            stationId: 'a',
            lineId: 'red',
            number: '2',
            towardsStationId: 'd',
            provenance: prov,
          ),
          // other direction: ignored
          Platform(
            stationId: 'a',
            lineId: 'red',
            number: '1',
            towardsStationId: 'a',
            provenance: prov,
          ),
          // no service and no direction: not specific enough
          Platform(
            stationId: 'c',
            lineId: 'blue',
            number: '9',
            provenance: prov,
          ),
        ],
      );
      final p = JourneyPlan.fromItinerary(s, best(s, 'a', 'y'));
      expect(p.steps[1].platform!.number, '2');
      expect(p.steps[1].platform!.provenance.sourceId, prov.sourceId);
      expect(p.steps[4].platform, isNull);
    });

    test('rows naming the service AND the other direction do not count '
        '(found by the M9 assistant corpus)', () {
      final s = net(
        platforms: const [
          Platform(
            stationId: 'b',
            lineId: 'red',
            number: '1',
            serviceId: 'red',
            towardsStationId: 'a',
            provenance: prov,
          ),
          Platform(
            stationId: 'b',
            lineId: 'red',
            number: '2',
            serviceId: 'red',
            towardsStationId: 'd',
            provenance: prov,
          ),
        ],
      );
      expect(
        JourneyPlan.fromItinerary(
          s,
          best(s, 'b', 'd'),
        ).steps[1].platform!.number,
        '2',
      );
      expect(
        JourneyPlan.fromItinerary(
          s,
          best(s, 'b', 'a'),
        ).steps[1].platform!.number,
        '1',
      );
    });

    test('two different platform numbers for one boarding = unknown', () {
      final s = net(
        platforms: const [
          Platform(
            stationId: 'a',
            lineId: 'red',
            number: '1',
            towardsStationId: 'd',
            provenance: prov,
          ),
          Platform(
            stationId: 'a',
            lineId: 'red',
            number: '2',
            serviceId: 'red',
            provenance: prov,
          ),
        ],
      );
      final p = JourneyPlan.fromItinerary(s, best(s, 'a', 'c'));
      expect(p.steps[1].platform, isNull);
    });

    test('gates: from data, ordered, closed ones left out, landmarks kept', () {
      final s = net(
        gates: const [
          Gate(id: 'c:g3', stationId: 'c', number: 3, provenance: prov),
          Gate(
            id: 'c:g1',
            stationId: 'c',
            number: 1,
            nameEn: 'North',
            hasLift: true,
            provenance: prov,
          ),
          Gate(
            id: 'c:g2',
            stationId: 'c',
            number: 2,
            isOpen: false,
            provenance: prov,
          ),
        ],
        landmarks: const [
          GateLandmark(
            gateId: 'c:g1',
            textEn: 'Test Mall',
            kind: GateLandmarkKind.landmark,
          ),
        ],
      );
      final p = JourneyPlan.fromItinerary(s, best(s, 'a', 'c'));
      final exit = p.steps.last;
      expect(exit.kind, JourneyStepKind.exit);
      expect(exit.gates.map((g) => g.number), [1, 3]);
      expect(exit.gates.first.landmarksEn, ['Test Mall']);
      expect(exit.gates.first.landmarksHi, [null]);
      expect(exit.gates.first.hasLift, isTrue);
      expect(exit.gates.last.hasLift, isNull);
      expect(p.steps.first.gates, isEmpty, reason: 'origin a has no gates');
    });

    test('signature ties the plan to the route', () {
      final it = best(net(), 'a', 'y');
      expect(JourneyPlan.fromItinerary(net(), it).signature, it.signature);
    });

    test('works on the TEST DATA fixture for every reachable pair', () {
      final s = loadFixture();
      final planner = RoutePlanner(s);
      var plans = 0;
      for (final a in s.stations) {
        for (final b in s.stations) {
          if (a.id == b.id) continue;
          final r = planner.plan(a.id, b.id);
          if (r.status != RouteStatus.ok) continue;
          final p = JourneyPlan.fromItinerary(s, r.itineraries.first);
          expect(p.steps.first.kind, JourneyStepKind.enter);
          expect(p.steps.last.kind, JourneyStepKind.exit);
          expect(p.fromId, a.id);
          expect(p.toId, b.id);
          plans++;
        }
      }
      expect(plans, greaterThan(20));
    });
  });

  group('engine', () {
    final plan = JourneyPlan.fromItinerary(net(), best(net(), 'a', 'y'));
    final engine = JourneyEngine(plan);
    // a -(100 s)- b -(100 s)- c : ride step 2 has 2 stops in 200 s

    JourneyState onTrain() =>
        engine.advance(engine.advance(JourneyState.start(t0), t0)!, t0)!;

    test('starts at "enter"; confirmations walk through the steps', () {
      var s = JourneyState.start(t0);
      final seen = <String>[];
      for (var i = 0; i < plan.steps.length; i++) {
        seen.add(engine.progress(s, t0).step.kind.name);
        final next = engine.advance(s, t0);
        if (next == null) break;
        s = next;
      }
      expect(seen, kinds(plan));
      expect(engine.advance(s, t0), isNull, reason: 'finished');
      expect(engine.progress(s, t0).isLastStep, isTrue);
    });

    test('ride: stops remaining follow the clock', () {
      final s = onTrain();
      expect(engine.progress(s, t0).step.kind, JourneyStepKind.ride);
      final at = engine.progress(s, t0);
      expect((at.positionIndex, at.stopsRemaining), (0, 2));
      expect(at.getOffNext, isFalse);
      final mid = engine.progress(s, t0 + 100 * 1000);
      expect((mid.positionIndex, mid.stopsRemaining), (1, 1));
      expect(mid.getOffNext, isTrue, reason: 'next stop is c');
      final end = engine.progress(s, t0 + 1000 * 1000);
      expect((end.positionIndex, end.stopsRemaining), (2, 0));
      expect(end.shouldBeThere, isTrue);
    });

    test('the clock never moves past the ride: getting off needs a tap', () {
      final s = onTrain();
      final late = engine.progress(s, t0 + 10 * 3600 * 1000);
      expect(late.step.kind, JourneyStepKind.ride);
      expect(late.stepIndex, 2);
      expect(late.positionIndex, 2);
    });

    test('a clock going backwards does not move the train back', () {
      final s = onTrain();
      final p = engine.progress(s, t0 - 60 * 1000);
      expect(p.positionIndex, 0);
    });

    test('"I am at b" on the train: the estimate continues from b', () {
      final s = engine.correctTo(onTrain(), 'b', t0 + 10)!;
      expect(s.stepIndex, 2);
      expect(s.rideBaseIndex, 1);
      final p = engine.progress(s, t0 + 10);
      expect((p.positionIndex, p.stopsRemaining), (1, 1));
    });

    test(
      '"I am at c" from the start: the change station, first match ahead',
      () {
        final s = engine.correctTo(JourneyState.start(t0), 'c', t0)!;
        // c is first the end of ride 1 (get off), then the change step
        expect(s.stepIndex, 2);
        expect(engine.progress(s, t0).shouldBeThere, isTrue);
        final after = engine.advance(s, t0)!;
        expect(engine.progress(after, t0).step.kind, JourneyStepKind.change);
        // saying "c" again while changing stays at the change
        expect(engine.correctTo(after, 'c', t0)!.stepIndex, after.stepIndex);
      },
    );

    test('a station only behind the rider moves back to it', () {
      var s = JourneyState.start(t0);
      for (var i = 0; i < 5; i++) {
        s = engine.advance(s, t0)!;
      }
      expect(engine.progress(s, t0).step.kind, JourneyStepKind.ride);
      final back = engine.correctTo(s, 'b', t0)!;
      expect(back.stepIndex, 2);
      expect(back.rideBaseIndex, 1);
    });

    test('a station not on the route is rejected', () {
      expect(engine.correctTo(JourneyState.start(t0), 'x', t0), isNull);
      expect(engine.correctTo(JourneyState.start(t0), 'nope', t0), isNull);
      expect(engine.correctableStations(), ['a', 'b', 'c', 'y']);
    });

    test('a corrupt or out-of-range state is clamped', () {
      final s = engine.normalise(
        const JourneyState(
          stepIndex: 99,
          startedAtMs: t0,
          stepStartedAtMs: t0,
          rideBaseIndex: 50,
        ),
      );
      expect(s.stepIndex, plan.lastIndex);
      expect(s.rideBaseIndex, 0);
      final ride = engine.normalise(
        const JourneyState(
          stepIndex: 2,
          startedAtMs: t0,
          stepStartedAtMs: t0,
          rideBaseIndex: 50,
        ),
      );
      expect(ride.rideBaseIndex, 2);
    });

    test('state round-trips through JSON; junk is refused', () {
      final s = engine.correctTo(onTrain(), 'b', t0 + 5)!;
      final back = JourneyState.fromJson(jsonDecode(jsonEncode(s.toJson())))!;
      expect(back.toJson(), s.toJson());
      for (final junk in <Object?>[
        null,
        'x',
        42,
        <String, Object>{},
        {'step': '1', 'startedAtMs': 1, 'stepStartedAtMs': 1, 'rideBase': 0},
        {'step': -1, 'startedAtMs': 1, 'stepStartedAtMs': 1, 'rideBase': 0},
      ]) {
        expect(JourneyState.fromJson(junk), isNull, reason: '$junk');
      }
    });

    test('deterministic: same plan, state and time, same progress', () {
      final a = JourneyEngine(
        JourneyPlan.fromItinerary(net(), best(net(), 'a', 'y')),
      );
      final s = onTrain();
      for (final dt in [0, 99999, 100000, 150000, 200000, 999999]) {
        final x = engine.progress(s, t0 + dt);
        final y = a.progress(s, t0 + dt);
        expect(
          (x.stepIndex, x.positionIndex, x.stopsRemaining, x.getOffNext),
          (y.stepIndex, y.positionIndex, y.stopsRemaining, y.getOffNext),
        );
      }
    });

    test('an itinerary without legs has no journey', () {
      expect(
        () => JourneyPlan.fromItinerary(
          net(),
          const Itinerary(
            profiles: [],
            legs: [],
            totalTimeS: 0,
            changes: 0,
            stops: 0,
            walkM: 0,
            assumptions: [],
            timeModelId: 't',
            warnings: [],
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  test('journey.dart is pure Dart: no Flutter, IO, network or plugins', () {
    final src = File('lib/src/journey/journey.dart').readAsStringSync();
    for (final m in RegExp(
      "^import '([^']+)';",
      multiLine: true,
    ).allMatches(src)) {
      expect(
        m.group(1)!.startsWith('package:metro_core/'),
        isTrue,
        reason: 'unexpected import ${m.group(1)}',
      );
    }
    expect(src.contains('DateTime.now'), isFalse, reason: 'no hidden clock');
  });
}
