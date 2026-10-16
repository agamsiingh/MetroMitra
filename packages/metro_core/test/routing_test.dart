import 'dart:math';

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/net_builder.dart';

RoutePlanner planner(MetroSnapshot s, {RoutingConfig? config}) =>
    RoutePlanner(s, config: config ?? const RoutingConfig());

Itinerary best(RoutePlanner p, String a, String b) {
  final r = p.plan(a, b);
  expect(r.status, RouteStatus.ok, reason: '${r.status} ${r.detail}');
  return r.best!;
}

/// Board wait of the default model.
const wait = 180;

void main() {
  group('single line', () {
    final p = planner(crossNet());

    test(
      'direct ride: time = wait + hops, no changes, terminal by direction',
      () {
        final it = best(p, 'a', 'e');
        expect(shape(it), 'R:a>b>c>d>e');
        expect(it.totalTimeS, wait + 4 * 100);
        expect(it.changes, 0);
        expect(it.stops, 4);
        final ride = it.legs.single as RideLeg;
        expect(ride.directionTerminalId, 'e');
        expect(ride.waitS, wait);
        expect(ride.distanceM, 4000);
        expect(ride.stopCount, 4);
        expect(best(p, 'e', 'a').rides.single.directionTerminalId, 'a');
      },
    );

    test('dataset travel times are used and not flagged as estimated', () {
      final it = best(p, 'a', 'c');
      expect((it.legs.single as RideLeg).rideEstimated, isFalse);
      expect(it.assumptions, [Assumption.boardingWait]);
      expect(it.timeModelId, 'fallback-v1');
    });

    test('sub-ranges ride the shorter way in either direction', () {
      expect(shape(best(p, 'd', 'b')), 'R:d>c>b');
    });

    test('total time equals the sum of leg durations', () {
      for (final (a, b) in [('a', 'y'), ('x', 'e'), ('b', 'd')]) {
        final it = best(p, a, b);
        expect(it.totalTimeS, it.legs.fold<int>(0, (s, l) => s + l.durationS));
      }
    });
  });

  group('travel-time fallback', () {
    test('unknown travel_s is estimated from distance and reported', () {
      final s = buildNet([
        const Svc('l', ['a', 'b', 'c'], hopS: [null, null]),
      ]);
      final it = best(planner(s), 'a', 'c');
      // dwell 25 + round(1000 * 3.6 / 35) = 25 + 103 per hop
      expect(it.totalTimeS, wait + 2 * 128);
      expect((it.legs.single as RideLeg).rideEstimated, isTrue);
      expect(it.assumptions, contains(Assumption.rideTimeEstimated));
      expect(it.timeIsEstimate, isTrue);
    });

    test('mixed: known hops keep their data value', () {
      final s = buildNet([
        const Svc('l', ['a', 'b', 'c'], hopS: [100, null]),
      ]);
      expect(best(planner(s), 'a', 'c').totalTimeS, wait + 100 + 128);
    });

    test('the model is configurable and its id is recorded', () {
      final s = buildNet([
        const Svc('l', ['a', 'b'], hopS: [null]),
      ]);
      final it = RoutePlanner(
        s,
        model: const TravelTimeModel(
          id: 'custom',
          cruiseSpeedKmh: 36,
          dwellS: 0,
          boardWaitS: 0,
        ),
      ).plan('a', 'b').best!;
      expect(it.totalTimeS, 100);
      expect(it.timeModelId, 'custom');
      expect(it.assumptions, [Assumption.rideTimeEstimated]);
    });

    test('model parameters are exported for audit', () {
      expect(
        const TravelTimeModel().toJson(),
        containsPair('board_wait_s', 180),
      );
    });
  });

  group('transfers', () {
    test('line change uses the transfer row (walk, step-free, provenance)', () {
      final it = best(planner(crossNet()), 'a', 'y');
      expect(shape(it), 'R:a>b>c|T:c|R:c>y');
      final t = it.legs[1] as TransferLeg;
      expect(t.kind, TransferKind.lineChange);
      expect(t.walkS, 60);
      expect(t.walkM, 50);
      expect(t.waitS, wait);
      expect(t.walkEstimated, isFalse);
      expect(t.stepFree, isTrue);
      expect(t.provenance?.sourceId, 'test-fixture');
      expect(it.totalTimeS, wait + 200 + 60 + wait + 100);
      expect(it.changes, 1);
      expect(it.walkM, 50);
      expect(it.warnings, isEmpty);
      expect(
        (it.legs.last as RideLeg).waitS,
        0,
        reason: 'the change already contains the wait',
      );
    });

    test('A->B and B->A have the same shape and time on a symmetric net', () {
      final p = planner(crossNet());
      final ab = best(p, 'a', 'y');
      final ba = best(p, 'y', 'a');
      expect(ba.changes, ab.changes);
      expect(ba.totalTimeS, ab.totalTimeS);
    });

    test('unknown walk time falls back, is reported and warned', () {
      final it = best(
        planner(crossNet(walkS: null, walkM: null)),
        'a',
        'y',
      );
      final t = it.legs[1] as TransferLeg;
      expect(t.walkS, 240);
      expect(t.walkM, 200);
      expect(t.walkEstimated, isTrue);
      expect(
        it.assumptions,
        containsAll([
          Assumption.transferWalkTimeEstimated,
          Assumption.transferWalkDistanceEstimated,
        ]),
      );
      expect(it.warnings.single.code, RouteWarningCode.unverifiedTransfer);
      expect(it.warnings.single.stationId, 'c');
    });

    test('only the missing half falls back', () {
      final t =
          best(planner(crossNet(walkM: null)), 'a', 'y').legs[1] as TransferLeg;
      expect(t.walkS, 60);
      expect(t.walkM, 200);
      expect(t.walkEstimated, isTrue);
    });

    test('no transfer row = no interchange (never invented)', () {
      final s = buildNet(const [
        Svc('red', ['a', 'b', 'c']),
        Svc('blue', ['x', 'c', 'y']),
      ]);
      final p = planner(s);
      expect(p.plan('a', 'y').status, RouteStatus.noRoute);
      expect(p.plan('a', 'c').status, RouteStatus.ok);
      expect(p.plan('x', 'c').status, RouteStatus.ok);
    });

    test('a one-directional row only allows that direction', () {
      final s = buildNet(
        const [
          Svc('red', ['a', 'b', 'c']),
          Svc('blue', ['x', 'c', 'y']),
        ],
        transfers: const [Xfer('c', 'red', 'blue', walkS: 60, walkM: 50)],
      );
      final p = planner(s);
      expect(p.plan('a', 'y').status, RouteStatus.ok);
      expect(p.plan('y', 'a').status, RouteStatus.noRoute);
    });

    test('two changes accumulate in order', () {
      final s = buildNet(
        const [
          Svc('l1', ['a', 'b']),
          Svc('l2', ['b', 'c']),
          Svc('l3', ['c', 'd']),
        ],
        transfers: const [
          Xfer('b', 'l1', 'l2', walkS: 30, walkM: 10),
          Xfer('c', 'l2', 'l3', walkS: 40, walkM: 20),
        ],
      );
      final it = best(planner(s), 'a', 'd');
      expect(shape(it), 'R:a>b|T:b|R:b>c|T:c|R:c>d');
      expect(it.changes, 2);
      expect(it.walkM, 30);
      expect(it.totalTimeS, wait + 100 + (30 + wait) + 100 + (40 + wait) + 100);
    });

    test('alighting and re-boarding cannot skip an interchange walk', () {
      // c has a walk link. Walking to z, boarding and alighting without
      // riding, then walking back must not beat the real interchange walk.
      final s = buildNet(
        const [
          Svc('red', ['a', 'b', 'c']),
          Svc('blue', ['c', 'd']),
          Svc('far', ['z', 'zz'], hopS: [1000]),
        ],
        transfers: const [Xfer('c', 'red', 'blue', walkS: 500, walkM: 5)],
        walks: const [Walk('w', 'c', 'z', 10, 10)],
      );
      final it = best(planner(s), 'a', 'd');
      expect((it.legs[1] as TransferLeg).walkS, 500);
    });
  });

  group('same-line services (branches)', () {
    final s = buildNet(const [
      Svc('main', ['a', 'b', 'c', 'd'], line: 'blue'),
      Svc('branch', ['c', 'e'], line: 'blue'),
    ]);
    final p = planner(s);

    test('staying on the trunk needs no change', () {
      expect(best(p, 'a', 'd').changes, 0);
    });

    test('changing between services of one line is an estimated change', () {
      final it = best(p, 'a', 'e');
      expect(shape(it), 'R:a>b>c|T:c|R:c>e');
      final t = it.legs[1] as TransferLeg;
      expect(t.kind, TransferKind.sameLineChange);
      expect(t.walkEstimated, isTrue);
      expect(it.warnings.single.code, RouteWarningCode.unverifiedTransfer);
    });
  });

  group('through-running services', () {
    final s = buildNet(const [
      Svc('t1', ['a', 'b', 'c'], line: 'l1', through: 't2'),
      Svc('t2', ['c', 'd', 'e'], line: 'l2'),
    ]);

    test('the train continues: zero-cost, zero-change connection', () {
      final it = best(planner(s), 'a', 'e');
      expect(shape(it), 'R:a>b>c|T:c|R:c>d>e');
      final t = it.legs[1] as TransferLeg;
      expect(t.kind, TransferKind.throughRunning);
      expect(t.durationS, 0);
      expect(it.changes, 0);
      expect(it.totalTimeS, wait + 200 + 200);
      expect(it.warnings, isEmpty);
    });

    test('works in the opposite direction too', () {
      final it = best(planner(s), 'e', 'a');
      expect(it.changes, 0);
      expect(it.totalTimeS, wait + 400);
    });

    test('without the declaration the lines are not connected', () {
      final none = buildNet(const [
        Svc('t1', ['a', 'b', 'c'], line: 'l1'),
        Svc('t2', ['c', 'd', 'e'], line: 'l2'),
      ]);
      expect(planner(none).plan('a', 'e').status, RouteStatus.noRoute);
    });
  });

  group('loop services', () {
    test('the closing edge is used; loops have no direction terminal', () {
      final s = buildNet(const [
        Svc('ring', ['a', 'b', 'c', 'd'], loop: true),
      ]);
      final it = best(planner(s), 'a', 'd');
      expect(shape(it), 'R:a>d');
      expect((it.legs.single as RideLeg).directionTerminalId, isNull);
    });
  });

  group('repeated stops (ring with a spur, e.g. Maujpur-Babarpur)', () {
    // Service P visits m twice: m a b m s. Hop times are set per test.
    MetroSnapshot ring(List<int?> hopS) => buildNet([
      Svc('p', const ['m', 'a', 'b', 'm', 's'], hopS: hopS),
    ]);

    test('riding on past the repeated station needs a change (the seam)', () {
      // Pink Line reality: the branch has its own services, riders change at
      // the junction. The data says nothing else, so a through ride is never
      // assumed.
      final it = best(planner(ring([100, 100, 100, 100])), 'a', 's');
      expect(shape(it), 'R:a>m|T:m|R:m>s');
      expect(it.changes, 1);
      expect((it.legs[1] as TransferLeg).kind, TransferKind.repeatedStop);
      expect(it.warnings.single.code, RouteWarningCode.repeatedStopChange);
    });

    test('a change at the seam can stay on the same visit', () {
      // Only the forward way exists here: arrive at the seam from b, then
      // change and carry on to s.
      final base = ring([100, 100, 100, 100]);
      final cut = base.copyWith(
        edges: [
          for (final e in base.edges)
            if (!(e.fromStation == 'a' && e.toStation == 'm')) e,
        ],
      );
      final it = best(planner(cut), 'a', 's');
      expect(shape(it), 'R:a>b>m|T:m|R:m>s');
      final t = it.legs[1] as TransferLeg;
      expect(t.fromServiceId, t.toServiceId);
      expect(it.totalTimeS, wait + 200 + 240 + wait + 100);
    });

    test('a ride that stops at the seam or starts there needs no change', () {
      final p = planner(ring([100, 100, 100, 100]));
      expect(best(p, 'a', 'b').changes, 0);
      expect(best(p, 'm', 's').changes, 0, reason: 'boards at the seam');
      expect(best(p, 's', 'm').changes, 0, reason: 'ends at the seam');
    });

    test('a ride cannot jump between the two visits of the station', () {
      // a -> m (first visit, 100 s) would continue to s for free if both visits
      // were one node. Making the forward way slow forces the other path.
      final it = best(planner(ring([100, 1000, 100, 100])), 'a', 's');
      expect(shape(it), 'R:a>m|T:m|R:m>s');
      final t = it.legs[1] as TransferLeg;
      expect(t.kind, TransferKind.repeatedStop);
      expect(t.fromServiceId, t.toServiceId);
      expect(it.changes, 1);
      expect(it.warnings.single.code, RouteWarningCode.repeatedStopChange);
      expect(it.warnings.single.stationId, 'm');
      // 100 ride + (240 walk + 180 wait) change + 100 ride + first wait
      expect(it.totalTimeS, wait + 100 + 240 + wait + 100);
    });

    test('a ring service claims no "towards" terminal', () {
      final it = best(planner(ring([100, 100, 100, 100])), 'a', 's');
      expect(it.rides.map((r) => r.directionTerminalId), everyElement(isNull));
    });

    test('the spur and the ring are both reachable from each other', () {
      final p = planner(ring([100, 100, 100, 100]));
      for (final (a, b) in [('s', 'a'), ('a', 's'), ('s', 'b'), ('m', 's')]) {
        expect(p.plan(a, b).status, RouteStatus.ok, reason: '$a>$b');
      }
      expect(shape(best(p, 's', 'a')), 'R:s>m|T:m|R:m>a');
    });

    test('the repeated station is reached at its cheaper visit', () {
      final it = best(planner(ring([100, 100, 100, 100])), 'm', 'b');
      expect(it.totalTimeS, wait + 100, reason: 'second visit, one hop back');
      expect(shape(it), 'R:m>b');
    });

    test('every pair is routable and visits stay in service order', () {
      final s = ring([100, 100, 100, 100]);
      final p = planner(s);
      final ids = [for (final st in s.stations) st.id];
      for (final a in ids) {
        for (final b in ids) {
          if (a == b) continue;
          final it = best(p, a, b);
          for (final r in it.rides) {
            expect(r.stopCount, greaterThan(0));
          }
        }
      }
    });
  });

  group('walk links', () {
    final s = loadFixture();
    final p = planner(s);

    test(
      'out-of-system walk between operators: legs, exit, separate ticket',
      () {
        final it = best(p, 'test-alpha', 'test-mu');
        expect(it.legs.map((l) => l.runtimeType.toString()), [
          'RideLeg',
          'WalkLeg',
          'RideLeg',
        ]);
        final w = it.legs[1] as WalkLeg;
        expect(w.requiresExit, isTrue);
        expect(w.walkS, 300);
        expect(w.walkM, 350);
        expect(w.provenance.sourceId, 'test-fixture');
        expect(it.changes, 1);
        expect(it.walkM, 350);
        expect(
          it.warnings.map((x) => x.code),
          contains(RouteWarningCode.separateTicket),
        );
        // red alpha->epsilon: 110+120+130+120 = 480 ; green kappa->mu: 150+140
        expect(it.totalTimeS, wait + 480 + 300 + wait + 290);
      },
    );

    test('the walk link works both ways', () {
      final it = best(p, 'test-mu', 'test-alpha');
      expect(it.legs.whereType<WalkLeg>().single.fromStationId, 'test-kappa');
    });

    test(
      'walks on both sides of a ride are allowed when the rider alights',
      () {
        final chain = buildNet(
          const [
            Svc('l1', ['a', 'b']),
            Svc('l2', ['c', 'd']),
            Svc('l3', ['e', 'f']),
          ],
          walks: const [
            Walk('w1', 'b', 'c', 60, 50, exit: true),
            Walk('w2', 'd', 'e', 60, 50, exit: true),
          ],
        );
        final it = best(planner(chain), 'a', 'f');
        expect(it.legs.whereType<WalkLeg>(), hasLength(2));
        expect(it.changes, 2);
      },
    );

    test('a walk that lands on the destination ends the trip', () {
      final it = best(
        planner(
          buildNet(
            const [
              Svc('l1', ['a', 'b']),
              Svc('l2', ['c', 'd']),
            ],
            walks: const [Walk('w', 'b', 'c', 60, 50, exit: true)],
          ),
        ),
        'a',
        'c',
      );
      expect(shape(it), 'R:a>b|W:b>c');
    });
  });

  group('profiles and alternatives', () {
    // Direct slow line vs. a quick three-line chain.
    MetroSnapshot net({int slow = 300}) => buildNet(
      [
        Svc(
          'slow',
          const ['s', 'm1', 'm2', 'm3', 't'],
          hopS: [slow, slow, slow, slow],
        ),
        const Svc('f1', ['s', 'p'], hopS: [100]),
        const Svc('f2', ['p', 'q'], hopS: [100]),
        const Svc('f3', ['q', 't'], hopS: [100]),
      ],
      transfers: const [
        Xfer('p', 'f1', 'f2', walkS: 60, walkM: 50),
        Xfer('q', 'f2', 'f3', walkS: 60, walkM: 50),
      ],
    );

    test('fastest, easiest and less-walking pick different routes', () {
      final r = planner(net()).plan('s', 't');
      expect(r.itineraries, hasLength(2));
      final quick = r.itineraries[0];
      final easy = r.itineraries[1];
      expect(quick.totalTimeS, wait + 100 + 240 + 100 + 240 + 100);
      expect(quick.changes, 2);
      expect(
        quick.profiles,
        [RoutingProfile.fastest, RoutingProfile.fewestStops],
      );
      expect(easy.totalTimeS, wait + 1200);
      expect(easy.changes, 0);
      expect(
        easy.profiles,
        [RoutingProfile.easiest, RoutingProfile.lessWalking],
      );
      expect(easy.walkM, 0);
      expect(quick.walkM, 100);
    });

    test('a hopeless detour is dropped by the guard rail', () {
      final r = planner(net(slow: 1000)).plan('s', 't');
      expect(r.itineraries, hasLength(1));
      expect(
        r.best!.profiles,
        [RoutingProfile.fastest, RoutingProfile.fewestStops],
        reason: 'easiest/less-walking were > 1.5x + 10 min and are discarded',
      );
    });

    test('identical results merge and carry every winning profile', () {
      final r = planner(crossNet()).plan('a', 'e');
      expect(r.itineraries, hasLength(1));
      expect(r.best!.profiles, RoutingProfile.values);
    });

    test('maxAlternatives limits the list', () {
      final r = planner(
        net(),
        config: const RoutingConfig(maxAlternatives: 1),
      ).plan('s', 't');
      expect(r.itineraries, hasLength(1));
    });

    test('each profile optimises its own cost order', () {
      final p = planner(net());
      final all = {
        for (final it in p.plan('s', 't').itineraries)
          for (final pr in it.profiles) pr: it,
      };
      final fastest = all[RoutingProfile.fastest]!;
      for (final it in all.values) {
        expect(fastest.totalTimeS, lessThanOrEqualTo(it.totalTimeS));
      }
      final easiest = all[RoutingProfile.easiest]!;
      for (final it in all.values) {
        expect(easiest.changes, lessThanOrEqualTo(it.changes));
      }
      final lessWalking = all[RoutingProfile.lessWalking]!;
      for (final it in all.values) {
        expect(lessWalking.walkM, lessThanOrEqualTo(it.walkM));
      }
      final fewest = all[RoutingProfile.fewestStops]!;
      for (final it in all.values) {
        expect(fewest.stops, lessThanOrEqualTo(it.stops));
      }
    });
  });

  group('failure modes', () {
    test('same station', () {
      expect(
        planner(crossNet()).plan('a', 'a').status,
        RouteStatus.sameStation,
      );
    });

    test('unknown station names the id', () {
      final r = planner(crossNet()).plan('a', 'nowhere');
      expect(r.status, RouteStatus.unknownStation);
      expect(r.detail, 'nowhere');
      expect(planner(crossNet()).plan('nowhere', 'a').detail, 'nowhere');
    });

    test('disconnected graph: noRoute, components reported', () {
      final s = buildNet(const [
        Svc('l1', ['a', 'b', 'c']),
        Svc('l2', ['x', 'y']),
      ]);
      final p = planner(s);
      final r = p.plan('a', 'x');
      expect(r.status, RouteStatus.noRoute);
      expect(r.itineraries, isEmpty);
      expect(p.stationComponents(), [
        ['a', 'b', 'c'],
        ['x', 'y'],
      ]);
      expect(p.plan('a', 'c').isOk, isTrue);
    });

    test('a connected network has one component', () {
      expect(planner(crossNet()).stationComponents(), hasLength(1));
      expect(planner(loadFixture()).stationComponents(), hasLength(1));
    });

    test('closed station: not routable, cannot be passed through', () {
      final s = buildNet(
        const [
          Svc('l', ['a', 'b', 'c']),
        ],
        closed: const {'b'},
      );
      final p = planner(s);
      expect(p.plan('a', 'b').status, RouteStatus.notServed);
      expect(p.plan('a', 'c').status, RouteStatus.noRoute);
    });

    test('a station on no open line is not served', () {
      final s = buildNet(const [
        Svc('l', ['a', 'b']),
        Svc('old', ['x', 'y'], lineStatus: OperatingStatus.closed),
      ]);
      expect(planner(s).plan('a', 'x').status, RouteStatus.notServed);
    });

    test('a missing edge is never invented', () {
      final s = crossNet();
      final cut = s.copyWith(
        edges: [
          for (final e in s.edges)
            if (!(e.serviceId == 'red' &&
                e.fromStation == 'b' &&
                e.toStation == 'c'))
              e,
        ],
      );
      final p = planner(cut);
      expect(p.plan('a', 'e').status, RouteStatus.noRoute);
      expect(p.plan('c', 'a').status, RouteStatus.ok);
      expect(p.plan('a', 'b').status, RouteStatus.ok);
    });

    test('an empty dataset routes nothing', () {
      final p = planner(MetroSnapshot(meta: const {}));
      expect(p.plan('a', 'b').status, RouteStatus.unknownStation);
      expect(p.stationComponents(), isEmpty);
    });
  });

  group('determinism', () {
    List<T> shuffled<T>(List<T> l, int seed) => [...l]..shuffle(Random(seed));

    MetroSnapshot reorder(MetroSnapshot s, int seed) => s.copyWith(
      stations: shuffled(s.stations, seed),
      services: shuffled(s.services, seed + 1),
      serviceStops: shuffled(s.serviceStops, seed + 2),
      edges: shuffled(s.edges, seed + 3),
      transfers: shuffled(s.transfers, seed + 4),
      walkLinks: shuffled(s.walkLinks, seed + 5),
    );

    test('equal-cost routes resolve the same way for any input order', () {
      final diamond = buildNet(const [
        Svc('one', ['s', 'a', 't']),
        Svc('two', ['s', 'b', 't']),
      ]);
      final expected = best(planner(diamond), 's', 't').signature;
      for (var seed = 0; seed < 8; seed++) {
        expect(
          best(planner(reorder(diamond, seed)), 's', 't').signature,
          expected,
          reason: 'seed $seed',
        );
      }
    });

    test('every fixture pair: same answer for any row order', () {
      final base = loadFixture();
      final ids = [for (final s in base.stations) s.id];
      final p0 = planner(base);
      final p1 = planner(reorder(base, 42));
      for (final a in ids) {
        for (final b in ids) {
          if (a == b) continue;
          final x = p0.plan(a, b);
          final y = p1.plan(a, b);
          expect(
            [for (final i in y.itineraries) i.signature],
            [for (final i in x.itineraries) i.signature],
            reason: '$a>$b',
          );
        }
      }
    });

    test('repeated queries give identical results', () {
      final p = planner(loadFixture());
      final a = p.plan('test-alpha', 'test-iota');
      final b = p.plan('test-alpha', 'test-iota');
      expect(a.best!.signature, b.best!.signature);
      expect(a.best!.totalTimeS, b.best!.totalTimeS);
    });
  });

  group('properties on the fixture network', () {
    final s = loadFixture();
    final p = planner(s);
    final ids = [for (final st in s.stations) st.id];
    final edgeKeys = {
      for (final e in s.edges) '${e.serviceId}|${e.fromStation}|${e.toStation}',
    };

    test('every station reaches every other station', () {
      for (final a in ids) {
        for (final b in ids) {
          if (a == b) continue;
          expect(p.plan(a, b).isOk, isTrue, reason: '$a>$b');
        }
      }
    });

    test('paths are made of real edges and legs connect end to start', () {
      for (final a in ids) {
        for (final b in ids) {
          if (a == b) continue;
          for (final it in p.plan(a, b).itineraries) {
            String? at = a;
            for (final l in it.legs) {
              switch (l) {
                case RideLeg():
                  expect(l.fromStationId, at, reason: '$a>$b');
                  for (var i = 0; i + 1 < l.stationIds.length; i++) {
                    expect(
                      edgeKeys,
                      contains(
                        '${l.serviceId}|${l.stationIds[i]}|${l.stationIds[i + 1]}',
                      ),
                    );
                  }
                  at = l.toStationId;
                case TransferLeg():
                  expect(l.stationId, at);
                case WalkLeg():
                  expect(l.fromStationId, at);
                  at = l.toStationId;
              }
            }
            expect(at, b, reason: '$a>$b');
            expect(
              it.totalTimeS,
              it.legs.fold<int>(0, (x, l) => x + l.durationS),
            );
          }
        }
      }
    });

    test('the fastest alternative is never beaten by another', () {
      for (final a in ids) {
        for (final b in ids) {
          if (a == b) continue;
          final r = p.plan(a, b);
          for (final it in r.itineraries) {
            expect(r.best!.totalTimeS, lessThanOrEqualTo(it.totalTimeS));
          }
        }
      }
    });

    test('A->B and B->A need the same number of changes', () {
      for (final a in ids) {
        for (final b in ids) {
          if (a.compareTo(b) >= 0) continue;
          expect(
            p.plan(a, b).best!.changes,
            p.plan(b, a).best!.changes,
            reason: '$a<>$b',
          );
        }
      }
    });

    test('known journeys on the fixture', () {
      final it = best(p, 'test-alpha', 'test-iota');
      expect(
        shape(it),
        'R:test-alpha>test-beta>test-gamma|T:test-gamma|R:test-gamma>test-theta>test-iota',
      );
      expect(it.totalTimeS, wait + 230 + 90 + wait + 240);
    });
  });
}
