import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/net_builder.dart';

FareSlab slab(int min, int? max, int paise, {DayType day = DayType.regular}) =>
    FareSlab(
      fareSystemId: 'fs',
      dayType: day,
      minKm: min,
      maxKm: max,
      amountPaise: paise,
    );

const fs = FareSystem(
  id: 'fs',
  operatorId: 'op-a',
  currency: 'INR',
  effectiveFrom: '2026-01-01',
  sourceId: 'test-fixture',
);

/// One line a-b-c-d-e, 1000 m hops, with the given fare tables.
MetroSnapshot line({
  List<FareSlab>? slabs,
  List<FareDiscount> discounts = const [],
  List<FareOverride> overrides = const [],
  bool withSystem = true,
}) => buildNet(
  const [
    Svc('l', ['a', 'b', 'c', 'd', 'e']),
  ],
  fareSystemOfOperator: withSystem ? const {'op-a': 'fs'} : const {},
  fareSystems: withSystem ? const [fs] : const [],
  slabs: slabs ?? [slab(0, 2, 1000), slab(2, 4, 2000), slab(4, null, 3000)],
  discounts: discounts,
  overrides: overrides,
);

FareQuote quote(
  MetroSnapshot s,
  String a,
  String b, [
  FareRequest r = const FareRequest(),
]) {
  final it = RoutePlanner(s).plan(a, b).best!;
  return FareEngine(s).quote(it.legs, r);
}

FareOverride override(
  String a,
  String b,
  int paise, {
  DayType day = DayType.regular,
}) => FareOverride(
  fareSystemId: 'fs',
  fromStation: a,
  toStation: b,
  dayType: day,
  amountPaise: paise,
  sourceId: 'test-fixture',
  verifiedOn: '2026-10-01',
);

const smart = FareDiscount(
  fareSystemId: 'fs',
  media: FareMedia.smartCard,
  kind: FareDiscountKind.base,
  percent: 10,
);
const offPeak = FareDiscount(
  fareSystemId: 'fs',
  media: FareMedia.smartCard,
  kind: FareDiscountKind.offPeak,
  percent: 10,
  windowsJson: '[{"days":"all","from":360,"to":480}]',
);
const card = FareRequest(media: FareMedia.smartCard);

void main() {
  group('slab fares', () {
    final s = line();

    test('picks the slab for the in-network distance', () {
      final q = quote(s, 'a', 'b');
      expect(q.isAvailable, isTrue);
      expect(q.totalPaise, 1000);
      expect(q.currency, 'INR');
      final seg = q.segments.single;
      expect(seg.distanceM, 1000);
      expect(seg.basis, FareBasis.slab);
      expect(seg.listedPaise, 1000);
      expect(seg.sourceId, 'test-fixture');
      expect(seg.fareSystemId, 'fs');
    });

    test('slabs are half-open [min, max): the boundary is the next slab', () {
      expect(quote(s, 'a', 'b').totalPaise, 1000);
      expect(quote(s, 'a', 'c').totalPaise, 2000); // exactly 2 km
      expect(quote(s, 'a', 'd').totalPaise, 2000); // 3 km
      expect(quote(s, 'a', 'e').totalPaise, 3000); // exactly 4 km, open slab
    });

    test('is symmetric when the data is', () {
      expect(quote(s, 'e', 'a').totalPaise, quote(s, 'a', 'e').totalPaise);
    });

    test('derived distance means derived confidence', () {
      expect(quote(s, 'a', 'c').confidence, Confidence.derived);
    });

    test('day type selects the slab table', () {
      final w = line(
        slabs: [
          slab(0, null, 1000),
          slab(0, null, 700, day: DayType.sundayHoliday),
        ],
      );
      expect(quote(w, 'a', 'c').totalPaise, 1000);
      const sunday = FareRequest(dayType: DayType.sundayHoliday);
      expect(quote(w, 'a', 'c', sunday).totalPaise, 700);
    });

    test('a day type without slabs has no fare (never reuses another)', () {
      const sunday = FareRequest(dayType: DayType.sundayHoliday);
      final q = quote(s, 'a', 'c', sunday);
      expect(q.status, FareStatus.unavailable);
      expect(q.segments.single.gap, FareGap.noSlab);
      expect(q.totalPaise, isNull);
    });

    test('a distance no slab covers has no fare', () {
      final q = quote(line(slabs: [slab(0, 2, 1000)]), 'a', 'd');
      expect(q.segments.single.gap, FareGap.noSlab);
      expect(q.segments.single.distanceM, 3000);
    });

    test(
      'fare distance is the shortest in-network one, not the ridden one',
      () {
        // The fastest ride goes round (quick hops); the fare uses the shortest
        // distance between the two stations.
        final n = buildNet(
          const [
            Svc('direct', ['s', 't'], hopM: [1000], hopS: [900]),
            Svc('round', ['s', 'm', 't'], hopM: [800, 800], hopS: [50, 50]),
          ],
          fareSystemOfOperator: const {'op-a': 'fs'},
          fareSystems: const [fs],
          slabs: [slab(0, 2, 1000), slab(2, null, 5000)],
        );
        final it = RoutePlanner(n).plan('s', 't').best!;
        expect(it.rides.single.serviceId, 'round');
        expect(it.rides.single.distanceM, 1600);
        final q = FareEngine(n).quote(it.legs);
        expect(q.segments.single.distanceM, 1000);
        expect(q.totalPaise, 1000);
      },
    );

    test('a change inside one operator is still one ticket', () {
      final withFares = crossNet().copyWith(
        operators: [
          const Operator(id: 'op-a', nameEn: 'A', fareSystemId: 'fs'),
        ],
        fareSystems: [fs],
        fareSlabs: [slab(0, null, 1234)],
      );
      final it = RoutePlanner(withFares).plan('a', 'y').best!;
      final q = FareEngine(withFares).quote(it.legs);
      expect(q.segments, hasLength(1));
      expect(q.separateTicket, isFalse);
      expect(q.segments.single.distanceM, 3000, reason: 'a-b-c then c-y');
      expect(q.totalPaise, 1234);
    });
  });

  group('overrides', () {
    test('a verified pair fare wins over the slab and is "verified"', () {
      final q = quote(line(overrides: [override('a', 'c', 2500)]), 'a', 'c');
      expect(q.totalPaise, 2500);
      expect(q.segments.single.basis, FareBasis.override);
      expect(q.confidence, Confidence.verified);
    });

    test('only for the exact direction and day type', () {
      final s = line(overrides: [override('a', 'c', 2500)]);
      expect(quote(s, 'c', 'a').totalPaise, 2000, reason: 'falls back to slab');
      const sunday = FareRequest(dayType: DayType.sundayHoliday);
      expect(quote(s, 'a', 'c', sunday).status, FareStatus.unavailable);
    });

    test('works without any slab', () {
      final s = line(slabs: [], overrides: [override('a', 'c', 2500)]);
      expect(quote(s, 'a', 'c').totalPaise, 2500);
    });

    test('discounts apply to an override like to a slab fare', () {
      final s = line(
        overrides: [override('a', 'c', 2500)],
        discounts: [smart],
      );
      expect(quote(s, 'a', 'c', card).totalPaise, 2250);
    });
  });

  group('discounts', () {
    test('token riders get no smart-card discount', () {
      expect(quote(line(discounts: [smart]), 'a', 'c').totalPaise, 2000);
    });

    test('smart-card base discount', () {
      final q = quote(line(discounts: [smart]), 'a', 'c', card);
      expect(q.totalPaise, 1800);
      expect(q.segments.single.listedPaise, 2000);
      expect(q.segments.single.discountPercent, 10);
      expect(q.segments.single.appliedDiscounts, ['base:10']);
    });

    test('off-peak is added inside its window only', () {
      final s = line(discounts: [smart, offPeak]);
      int at(int minute) => quote(
        s,
        'a',
        'c',
        FareRequest(media: FareMedia.smartCard, minuteOfDay: minute),
      ).totalPaise!;
      expect(at(420), 1600, reason: '20% off');
      expect(at(360), 1600, reason: 'window start is inclusive');
      expect(at(480), 1800, reason: 'window end is exclusive');
      expect(at(900), 1800);
    });

    test('unknown time: off-peak is not applied and the quote says so', () {
      final q = quote(line(discounts: [smart, offPeak]), 'a', 'c', card);
      expect(q.totalPaise, 1800);
      expect(q.segments.single.notes.single, contains('time unknown'));
    });

    test('windows can be restricted to a day type', () {
      const sundayOnly = FareDiscount(
        fareSystemId: 'fs',
        media: FareMedia.any,
        kind: FareDiscountKind.offPeak,
        percent: 50,
        windowsJson: '[{"days":"sunday_holiday","from":0,"to":1440}]',
      );
      final s = line(
        slabs: [
          slab(0, null, 1000),
          slab(0, null, 1000, day: DayType.sundayHoliday),
        ],
        discounts: [sundayOnly],
      );
      expect(
        quote(s, 'a', 'c', const FareRequest(minuteOfDay: 600)).totalPaise,
        1000,
      );
      const sundayAt10 = FareRequest(
        dayType: DayType.sundayHoliday,
        minuteOfDay: 600,
      );
      expect(quote(s, 'a', 'c', sundayAt10).totalPaise, 500);
    });

    test('rounds half up to whole paise (integer arithmetic)', () {
      final s = line(slabs: [slab(0, null, 1005)], discounts: [smart]);
      expect(quote(s, 'a', 'b', card).totalPaise, 905);
    });

    test('percentages are capped at 100', () {
      const big = FareDiscount(
        fareSystemId: 'fs',
        media: FareMedia.any,
        kind: FareDiscountKind.base,
        percent: 80,
      );
      expect(quote(line(discounts: [big, big]), 'a', 'b').totalPaise, 0);
    });

    test('an unreadable window makes the fare unavailable (fail closed)', () {
      const broken = FareDiscount(
        fareSystemId: 'fs',
        media: FareMedia.any,
        kind: FareDiscountKind.offPeak,
        percent: 10,
        windowsJson: 'not json',
      );
      final q = quote(
        line(discounts: [broken]),
        'a',
        'b',
        const FareRequest(minuteOfDay: 400),
      );
      expect(q.segments.single.gap, FareGap.badDiscountWindow);
      expect(q.totalPaise, isNull);
    });
  });

  group('no fare data (the real draft dataset today)', () {
    test('operator without a fare system: unavailable, nothing invented', () {
      final q = quote(line(withSystem: false), 'a', 'c');
      expect(q.status, FareStatus.unavailable);
      expect(q.totalPaise, isNull);
      expect(q.currency, isNull);
      expect(q.confidence, isNull);
      expect(q.segments.single.gap, FareGap.noFareSystem);
      expect(q.segments.single.amountPaise, isNull);
    });

    test('a fare system with no slabs, overrides or discounts has no fare', () {
      final q = quote(line(slabs: []), 'a', 'c');
      expect(q.segments.single.gap, FareGap.noSlab);
    });

    test('a planner without a fare engine reports no fare', () {
      final it = RoutePlanner(line()).plan('a', 'c').best!;
      expect(it.fare!.status, FareStatus.unavailable);
      expect(it.fare!.notes, isNotEmpty);
    });

    test('no rides: nothing to price', () {
      expect(FareEngine(line()).quote(const []).status, FareStatus.unavailable);
    });
  });

  group('tickets: operators and exits', () {
    final s = loadFixture();
    final planner = RoutePlanner(s, fareEngine: FareEngine(s));

    test('two operators across an out-of-system walk: two tickets, summed', () {
      final it = planner.plan('test-alpha', 'test-mu').best!;
      final q = it.fare!;
      expect(q.status, FareStatus.available);
      expect(q.separateTicket, isTrue);
      expect(q.segments.map((x) => x.operatorId), ['test-op-a', 'test-op-b']);
      // A: alpha->epsilon 5200 m = 3000; B: kappa->mu 3300 m = 1500 (open slab)
      expect(q.segments.map((x) => x.amountPaise), [3000, 1500]);
      expect(q.totalPaise, 4500);
      expect(
        it.warnings.map((w) => w.code),
        contains(RouteWarningCode.separateTicket),
      );
    });

    test('fixture override: verified pair fare', () {
      final q = planner.plan('test-alpha', 'test-zeta').best!.fare!;
      expect(q.totalPaise, 5000);
      expect(q.segments.single.basis, FareBasis.override);
    });

    test('fixture smart-card + off-peak (10% + 10%)', () {
      final it = planner.plan('test-alpha', 'test-epsilon').best!;
      final q = FareEngine(s).quote(
        it.legs,
        const FareRequest(media: FareMedia.smartCard, minuteOfDay: 400),
      );
      expect(q.totalPaise, 2400); // 3000 - 20%
    });

    test('one operator via two lines: one ticket, shortest distance', () {
      final q = planner.plan('test-alpha', 'test-iota').best!.fare!;
      expect(q.segments, hasLength(1));
      expect(q.segments.single.distanceM, 5600);
      expect(q.totalPaise, 3000);
      expect(q.separateTicket, isFalse);
    });

    test('exiting the paid area splits tickets even for one operator', () {
      final n = buildNet(
        const [
          Svc('l1', ['a', 'b']),
          Svc('l2', ['c', 'd']),
        ],
        walks: const [Walk('w', 'b', 'c', 60, 50, exit: true)],
        fareSystemOfOperator: const {'op-a': 'fs'},
        fareSystems: const [fs],
        slabs: [slab(0, null, 1000)],
      );
      final q = FareEngine(n).quote(RoutePlanner(n).plan('a', 'd').best!.legs);
      expect(q.segments, hasLength(2));
      expect(q.totalPaise, 2000);
      expect(q.separateTicket, isTrue);
    });

    test('one priced and one unpriced segment is partial, with no total', () {
      final n = buildNet(
        const [
          Svc('l1', ['a', 'b']),
          Svc('l2', ['c', 'd'], op: 'op-b'),
        ],
        walks: const [Walk('w', 'b', 'c', 60, 50, exit: true)],
        fareSystemOfOperator: const {'op-a': 'fs'},
        fareSystems: const [fs],
        slabs: [slab(0, null, 1000)],
      );
      final q = FareEngine(n).quote(RoutePlanner(n).plan('a', 'd').best!.legs);
      expect(q.status, FareStatus.partial);
      expect(q.totalPaise, isNull);
      expect(q.segments.first.priced, isTrue);
      expect(q.segments.last.gap, FareGap.noFareSystem);
    });

    test('ticketSegments groups consecutive rides per operator', () {
      final it = planner.plan('test-alpha', 'test-mu').best!;
      expect(ticketSegments(it.legs).map((g) => g.length), [1, 1]);
    });
  });
}
