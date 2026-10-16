import 'dart:io';

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

Station st(
  String id,
  double lat,
  double lng, {
  OperatingStatus status = OperatingStatus.open,
}) => Station(
  id: id,
  nameEn: id,
  lat: lat,
  lng: lng,
  status: status,
  provenance: prov,
);

void main() {
  // Invented points along a meridian: 0.001 degree of latitude ~ 111 m.
  final stations = [
    st('far', 10.05, 20),
    st('b', 10.002, 20),
    st('a', 10.001, 20),
    st('closed', 10.0005, 20, status: OperatingStatus.closed),
    st('bad-nan', double.nan, 20),
    st('bad-range', 95, 20),
    st('bad-zero', 0, 0),
  ];

  test('haversine: known distances', () {
    expect(straightLineDistanceM(10, 20, 10, 20), 0);
    // one degree of latitude on the mean-radius sphere
    expect(straightLineDistanceM(10, 20, 11, 20), closeTo(111195, 5));
    expect(
      straightLineDistanceM(10, 20, 10.001, 20),
      closeTo(straightLineDistanceM(10.001, 20, 10, 20), 1e-9),
    );
  });

  test('nearest first, in whole metres, bad and closed stations skipped', () {
    final r = findNearbyStations(stations, lat: 10, lng: 20);
    expect(r.map((x) => x.station.id), ['a', 'b']);
    expect(r.first.distanceM, closeTo(111, 1));
    expect(r.last.distanceM, closeTo(222, 1));
  });

  test('radius and limit apply; far station only inside a wide radius', () {
    expect(
      findNearbyStations(
        stations,
        lat: 10,
        lng: 20,
        maxDistanceM: 150,
      ).map((x) => x.station.id),
      ['a'],
    );
    expect(
      findNearbyStations(
        stations,
        lat: 10,
        lng: 20,
        maxDistanceM: 10000,
        limit: 2,
      ).map((x) => x.station.id),
      ['a', 'b'],
    );
    expect(
      findNearbyStations(
        stations,
        lat: 10,
        lng: 20,
        maxDistanceM: 10000,
      ).map((x) => x.station.id),
      ['a', 'b', 'far'],
    );
  });

  test('onlyOpen:false keeps closed stations', () {
    final r = findNearbyStations(stations, lat: 10, lng: 20, onlyOpen: false);
    expect(r.map((x) => x.station.id), ['closed', 'a', 'b']);
  });

  test(
    'equal distances are ordered by station id, whatever the input order',
    () {
      final tie = [
        st('z', 10, 20.001),
        st('m', 10, 20.001),
        st('c', 10, 19.999),
      ];
      final a = findNearbyStations(tie, lat: 10, lng: 20);
      final b = findNearbyStations(tie.reversed, lat: 10, lng: 20);
      expect(a.map((x) => x.distanceM).toSet().length, 1);
      expect(a.map((x) => x.station.id), ['c', 'm', 'z']);
      expect(b.map((x) => x.station.id), ['c', 'm', 'z']);
    },
  );

  test('invalid query points give nothing', () {
    for (final p in [
      (double.nan, 20.0),
      (91.0, 20.0),
      (10.0, 181.0),
      (0.0, 0.0),
      (double.infinity, 1.0),
    ]) {
      expect(isValidCoordinate(p.$1, p.$2), isFalse);
      expect(findNearbyStations(stations, lat: p.$1, lng: p.$2), isEmpty);
    }
    expect(isValidCoordinate(null, 20), isFalse);
    expect(isValidCoordinate(10, 20), isTrue);
  });

  test('works on the TEST DATA fixture and is deterministic', () {
    final s = loadFixture();
    final first = s.stations.first;
    final a = findNearbyStations(
      s.stations,
      lat: first.lat,
      lng: first.lng,
      maxDistanceM: 10000000,
      limit: 100,
    );
    final b = findNearbyStations(
      s.stations.reversed,
      lat: first.lat,
      lng: first.lng,
      maxDistanceM: 10000000,
      limit: 100,
    );
    expect(a.first.station.id, first.id);
    expect(a.first.distanceM, 0);
    expect(
      a.map((x) => x.station.id).toList(),
      b.map((x) => x.station.id).toList(),
    );
  });

  test('nearby.dart is pure Dart: no Flutter, IO, network or plugins', () {
    final src = File('lib/src/geo/nearby.dart').readAsStringSync();
    final imports = RegExp(
      "^import '([^']+)';",
      multiLine: true,
    ).allMatches(src).map((m) => m.group(1)!).toList();
    expect(imports, isNotEmpty);
    for (final i in imports) {
      expect(
        i == 'dart:math' || i.startsWith('package:metro_core/'),
        isTrue,
        reason: 'unexpected import $i',
      );
    }
  });
}
