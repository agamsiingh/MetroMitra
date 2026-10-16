import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/net_builder.dart';

void main() {
  final s = loadFixture();
  final p = RoutePlanner(s);
  Itinerary it(String a, String b) => p.plan(a, b).best!;
  List<RouteWarningCode> codes(List<RouteWarning> w) => [
    for (final x in w) x.code,
  ];

  // Red alpha->zeta regular: last departure 23:00 (1380 min). Board wait 180 s.
  test('a boarding before the last departure is fine', () {
    expect(
      checkLastTrain(s, it('test-alpha', 'test-zeta'), departMinute: 1376),
      isEmpty,
    );
  });

  test('exactly at the last departure is still fine', () {
    // 1377 min + 180 s wait = 1380 min
    expect(
      checkLastTrain(s, it('test-alpha', 'test-zeta'), departMinute: 1377),
      isEmpty,
    );
  });

  test('a boarding after the last departure is a risk', () {
    final w = checkLastTrain(
      s,
      it('test-alpha', 'test-zeta'),
      departMinute: 1378,
    );
    expect(codes(w), [RouteWarningCode.lastTrainRisk]);
    expect(w.single.stationId, 'test-alpha');
    expect(w.single.legIndex, 0);
  });

  test('direction matters: the opposite direction has its own last train', () {
    // zeta -> alpha last dep 1410
    expect(
      checkLastTrain(s, it('test-zeta', 'test-alpha'), departMinute: 1400),
      isEmpty,
    );
    expect(
      codes(
        checkLastTrain(s, it('test-zeta', 'test-alpha'), departMinute: 1408),
      ),
      [RouteWarningCode.lastTrainRisk],
    );
  });

  test('day type selects the timing row', () {
    expect(
      checkLastTrain(
        s,
        it('test-alpha', 'test-zeta'),
        departMinute: 1377,
        dayType: DayType.sundayHoliday,
      ),
      isEmpty,
    );
  });

  test('post-midnight service minutes (> 1440) are understood', () {
    // blue eta->iota last dep 1470 (00:30)
    expect(
      checkLastTrain(s, it('test-eta', 'test-iota'), departMinute: 1460),
      isEmpty,
    );
    expect(
      codes(checkLastTrain(s, it('test-eta', 'test-iota'), departMinute: 1468)),
      [RouteWarningCode.lastTrainRisk],
    );
  });

  test('no timing row = unknown, never "a train will run"', () {
    // The blue boarding at gamma (after a change) has no timing in the fixture.
    final w = checkLastTrain(
      s,
      it('test-alpha', 'test-iota'),
      departMinute: 600,
    );
    expect(codes(w), [RouteWarningCode.lastTrainUnknown]);
    expect(w.single.stationId, 'test-gamma');
  });

  test(
    'a late first leg is flagged while the unknown second stays unknown',
    () {
      final w = checkLastTrain(
        s,
        it('test-alpha', 'test-iota'),
        departMinute: 1379,
      );
      expect(codes(w), [
        RouteWarningCode.lastTrainRisk,
        RouteWarningCode.lastTrainUnknown,
      ]);
    },
  );

  test('loops have no direction terminal, so they are unknown', () {
    final n = buildNet(const [
      Svc('ring', ['a', 'b', 'c'], loop: true),
    ]);
    final w = checkLastTrain(
      n,
      RoutePlanner(n).plan('a', 'b').best!,
      departMinute: 600,
    );
    expect(codes(w), [RouteWarningCode.lastTrainUnknown]);
  });

  test('a dataset with no timings at all: unknown for every boarding', () {
    final n = crossNet();
    final w = checkLastTrain(
      n,
      RoutePlanner(n).plan('a', 'y').best!,
      departMinute: 600,
    );
    expect(codes(w), [
      RouteWarningCode.lastTrainUnknown,
      RouteWarningCode.lastTrainUnknown,
    ]);
  });
}
