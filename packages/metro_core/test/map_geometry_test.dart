import 'dart:io';
import 'dart:math' as math;

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

Station st(String id, double lat, double lng) => Station(
  id: id,
  nameEn: 'Pt $id',
  lat: lat,
  lng: lng,
  status: OperatingStatus.open,
  provenance: prov,
);

/// A line of N stations along a diagonal, one service, invented.
MetroSnapshot lineOf(
  List<Station> stations, {
  List<String>? order,
  String line = 'l1',
}) {
  final base = loadFixture();
  final ids = order ?? [for (final s in stations) s.id];
  return base.copyWith(
    stations: stations,
    lines: [
      Line(
        id: line,
        operatorId: base.operators.first.id,
        nameEn: 'Test $line',
        colorHex: '#123456',
        textColorHex: '#FFFFFF',
        sort: 1,
        status: OperatingStatus.open,
      ),
    ],
    services: [LineService(id: 's1', lineId: line, name: 's1')],
    serviceStops: [
      for (var i = 0; i < ids.length; i++)
        ServiceStop(
          serviceId: 's1',
          seq: i,
          stationId: ids[i],
          distFromStartM: i,
        ),
    ],
    stationLines: [
      for (final id in ids) StationLine(stationId: id, lineId: line),
    ],
    edges: const [],
    transfers: const [],
    walkLinks: const [],
  );
}

void main() {
  final pts = [
    st('a', 28.60, 77.10),
    st('b', 28.61, 77.11),
    st('c', 28.62, 77.12),
  ];

  group('geometry', () {
    test('stations ordered by id; segments one per consecutive pair', () {
      final g = MapGeometry.fromSnapshot(lineOf(pts.reversed.toList()));
      expect(g.stations.map((s) => s.id), ['a', 'b', 'c']);
      expect(g.segments.map((s) => s.key), ['l1|a|b', 'l1|b|c']);
      expect(g.skippedStationIds, isEmpty);
      expect(g.skippedSegmentCount, 0);
    });

    test('input order never changes the result', () {
      final a = MapGeometry.fromSnapshot(lineOf(pts, order: ['a', 'b', 'c']));
      final b = MapGeometry.fromSnapshot(
        lineOf(pts.reversed.toList(), order: ['a', 'b', 'c']),
      );
      expect(
        a.stations.map((s) => '${s.id}:${s.x}:${s.y}').toList(),
        b.stations.map((s) => '${s.id}:${s.x}:${s.y}').toList(),
      );
      expect(
        a.segments.map((s) => s.key).toList(),
        b.segments.map((s) => s.key).toList(),
      );
      expect(a.networkFrame.toString(), b.networkFrame.toString());
    });

    test('plane: east is +x, north is -y (screen orientation)', () {
      final g = MapGeometry.fromSnapshot(lineOf(pts));
      expect(g.station('c')!.x, greaterThan(g.station('a')!.x));
      expect(g.station('c')!.y, lessThan(g.station('a')!.y));
      // 0.02 degrees of latitude apart
      expect(g.station('a')!.y - g.station('c')!.y, closeTo(0.02, 1e-6));
      // longitude is scaled by cos(latitude)
      expect(
        g.station('c')!.x - g.station('a')!.x,
        closeTo(0.02 * math.cos(28.61 * math.pi / 180), 1e-6),
      );
    });

    test('a segment is shared by services of one line, not doubled', () {
      final base = lineOf(pts);
      final snap = base.copyWith(
        services: [
          ...base.services,
          const LineService(id: 's2', lineId: 'l1', name: 's2'),
        ],
        serviceStops: [
          ...base.serviceStops,
          const ServiceStop(
            serviceId: 's2',
            seq: 0,
            stationId: 'c',
            distFromStartM: 0,
          ),
          const ServiceStop(
            serviceId: 's2',
            seq: 1,
            stationId: 'b',
            distFromStartM: 1,
          ),
        ],
      );
      expect(MapGeometry.fromSnapshot(snap).segments, hasLength(2));
    });

    test('interchange = on two or more lines', () {
      final base = lineOf(pts);
      final snap = base.copyWith(
        stationLines: [
          ...base.stationLines,
          const StationLine(stationId: 'b', lineId: 'l2'),
        ],
      );
      final g = MapGeometry.fromSnapshot(snap);
      expect(g.station('b')!.isInterchange, isTrue);
      expect(g.station('b')!.lineIds, ['l1', 'l2']);
      expect(g.station('a')!.isInterchange, isFalse);
    });

    test('invalid coordinates: skipped and counted, never guessed', () {
      final g = MapGeometry.fromSnapshot(
        lineOf(
          [
            st('a', 28.60, 77.10),
            st('nan', double.nan, 77.1),
            st('far', 120, 77.1),
            st('zero', 0, 0),
            st('c', 28.62, 77.12),
          ],
          order: ['a', 'nan', 'c', 'far', 'zero'],
        ),
      );
      expect(g.stations.map((s) => s.id), ['a', 'c']);
      expect(g.skippedStationIds, ['far', 'nan', 'zero']);
      // a-nan, nan-c, c-far, far-zero are undrawable
      expect(g.segments, isEmpty);
      expect(g.skippedSegmentCount, 4);
    });

    test('empty network', () {
      final g = MapGeometry.fromSnapshot(lineOf(const []));
      expect(g.isEmpty, isTrue);
      expect(g.networkFrame, isNull);
      expect(g.framingFor(['a']), isNull);
      expect(g.nearestStation(0, 0, 1), isNull);
    });

    test('works on the TEST DATA fixture', () {
      final snap = loadFixture();
      final g = MapGeometry.fromSnapshot(snap);
      expect(g.stations, hasLength(snap.stations.length));
      expect(g.segments, isNotEmpty);
      for (final s in g.segments) {
        expect(g.station(s.fromId), isNotNull);
        expect(g.station(s.toId), isNotNull);
        expect(s.fromId.compareTo(s.toId), lessThan(0));
      }
    });
  });

  group('user position (live tracking)', () {
    test('the coordinates of a station project onto that station', () {
      final g = MapGeometry.fromSnapshot(lineOf(pts));
      for (final s in pts) {
        final (x, y) = g.project(s.lat, s.lng)!;
        expect(x, closeTo(g.station(s.id)!.x, 1e-6));
        expect(y, closeTo(g.station(s.id)!.y, 1e-6));
      }
    });

    test('invalid points and empty networks give null, never (0, 0)', () {
      final g = MapGeometry.fromSnapshot(lineOf(pts));
      expect(g.project(0, 0), isNull);
      expect(g.project(double.nan, 77), isNull);
      expect(g.project(95, 77), isNull);
      final empty = MapGeometry.fromSnapshot(lineOf(const []));
      expect(empty.project(28.6, 77.1), isNull);
    });

    test('framing with a point includes both the point and the stations', () {
      final g = MapGeometry.fromSnapshot(lineOf(pts));
      final p = g.project(28.70, 77.20)!;
      final f = g.framingWith(['a'], [p])!;
      final a = g.station('a')!;
      expect(f.minX <= a.x && a.x <= f.maxX, isTrue);
      expect(f.minX <= p.$1 && p.$1 <= f.maxX, isTrue);
      expect(f.minY <= p.$2 && p.$2 <= f.maxY, isTrue);
      expect(g.framingWith(const [], const []), isNull);
    });
  });

  group('framing', () {
    test('whole network covers every station', () {
      final g = MapGeometry.fromSnapshot(lineOf(pts));
      final f = g.networkFrame!;
      for (final s in g.stations) {
        expect(s.x, inInclusiveRange(f.minX, f.maxX));
        expect(s.y, inInclusiveRange(f.minY, f.maxY));
      }
    });

    test('a route frames exactly its stations', () {
      final g = MapGeometry.fromSnapshot(lineOf(pts));
      final f = g.framingFor(['a', 'b'])!;
      expect(f.minX, closeTo(g.station('a')!.x, 1e-9));
      expect(f.maxX, closeTo(g.station('b')!.x, 1e-9));
      expect(f.minY, closeTo(g.station('b')!.y, 1e-9));
      expect(f.maxY, closeTo(g.station('a')!.y, 1e-9));
    });

    test('frame ignores unknown ids and is order independent', () {
      final g = MapGeometry.fromSnapshot(lineOf(pts));
      expect(
        g.framingFor(['c', 'nope', 'a']).toString(),
        g.framingFor(['a', 'c']).toString(),
      );
      expect(g.framingFor(['nope']), isNull);
    });

    test('one station, or several at the same spot: a minimum span', () {
      final g = MapGeometry.fromSnapshot(
        lineOf([
          st('a', 28.6, 77.1),
          st('b', 28.6, 77.1),
          st('c', 28.6000001, 77.1000001),
        ]),
      );
      final one = g.framingFor(['a'])!;
      expect(one.width, closeTo(MapGeometry.minSpan, 1e-12));
      expect(one.height, closeTo(MapGeometry.minSpan, 1e-12));
      final same = g.framingFor(['a', 'b', 'c'])!;
      expect(same.width, closeTo(MapGeometry.minSpan, 1e-12));
      expect(same.height, closeTo(MapGeometry.minSpan, 1e-12));
      final hood = g.framingForStation('a')!;
      expect(hood.width, closeTo(MapGeometry.stationSpan, 1e-12));
      expect(hood.centerX, closeTo(g.station('a')!.x, 1e-6));
    });

    test('the same input gives bit-identical frames', () {
      final frames = {
        for (var i = 0; i < 5; i++)
          MapGeometry.fromSnapshot(lineOf(pts)).networkFrame.toString(),
      };
      expect(frames, hasLength(1));
    });
  });

  group('hit test', () {
    final g = MapGeometry.fromSnapshot(
      lineOf([
        st('a', 28.6, 77.1),
        st('b', 28.6, 77.1),
        st('c', 28.601, 77.1),
        st('d', 28.7, 77.1),
      ]),
    );

    test('nearest station within range, by id on ties', () {
      final a = g.station('a')!;
      expect(g.nearestStation(a.x, a.y, 0.0005)!.id, 'a'); // a and b coincide
      final c = g.station('c')!;
      expect(g.nearestStation(c.x, c.y + 0.0001, 0.0005)!.id, 'c');
    });

    test('nothing in range, bad input', () {
      expect(g.nearestStation(5, 5, 0.001), isNull);
      expect(g.nearestStation(double.nan, 0, 0.001), isNull);
      expect(g.nearestStation(0, 0, 0), isNull);
    });

    test('range may span several grid cells', () {
      final d = g.station('d')!;
      expect(g.nearestStation(d.x + 0.02, d.y, 0.03)!.id, 'd');
    });
  });

  test('a large invented network builds quickly and hit-tests fast', () {
    // 3000 stations on 30 lines of 100: far more than any real network
    final list = <Station>[];
    for (var l = 0; l < 30; l++) {
      for (var i = 0; i < 100; i++) {
        list.add(st('l$l-$i', 28.4 + l * 0.01 + i * 0.0001, 76.9 + i * 0.003));
      }
    }
    final base = loadFixture();
    final snap = base.copyWith(
      stations: list,
      lines: [
        for (var l = 0; l < 30; l++)
          Line(
            id: 'l$l',
            operatorId: base.operators.first.id,
            nameEn: 'L$l',
            colorHex: '#123456',
            textColorHex: '#FFFFFF',
            sort: l,
            status: OperatingStatus.open,
          ),
      ],
      services: [
        for (var l = 0; l < 30; l++)
          LineService(id: 's$l', lineId: 'l$l', name: 's$l'),
      ],
      serviceStops: [
        for (var l = 0; l < 30; l++)
          for (var i = 0; i < 100; i++)
            ServiceStop(
              serviceId: 's$l',
              seq: i,
              stationId: 'l$l-$i',
              distFromStartM: i,
            ),
      ],
      stationLines: [
        for (var l = 0; l < 30; l++)
          for (var i = 0; i < 100; i++)
            StationLine(stationId: 'l$l-$i', lineId: 'l$l'),
      ],
      edges: const [],
      transfers: const [],
      walkLinks: const [],
    );
    final sw = Stopwatch()..start();
    final g = MapGeometry.fromSnapshot(snap);
    final build = sw.elapsedMilliseconds;
    expect(g.stations, hasLength(3000));
    expect(g.segments, hasLength(30 * 99));
    sw
      ..reset()
      ..start();
    for (var i = 0; i < 1000; i++) {
      g.nearestStation(0.01 * (i % 50), 0.01 * (i % 30), 0.003);
    }
    final taps = sw.elapsedMilliseconds;
    // generous bounds: this guards against quadratic work, not machine speed
    expect(build, lessThan(3000), reason: 'build $build ms');
    expect(taps, lessThan(1500), reason: '1000 taps $taps ms');
  });

  test('map_geometry.dart is pure Dart: no Flutter, IO, network, plugins', () {
    final src = File('lib/src/map/map_geometry.dart').readAsStringSync();
    for (final m in RegExp(
      "^import '([^']+)';",
      multiLine: true,
    ).allMatches(src)) {
      final i = m.group(1)!;
      expect(
        i == 'dart:math' || i.startsWith('package:metro_core/'),
        isTrue,
        reason: 'unexpected import $i',
      );
    }
  });
}
