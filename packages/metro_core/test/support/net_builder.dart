import 'package:metro_core/metro_core.dart';

import 'fixture.dart';

/// A service of a synthetic (TEST DATA) network. Stations are created from the
/// stop ids; edges are generated in both directions.
class Svc {
  const Svc(
    this.id,
    this.stops, {
    this.line,
    this.op = 'op-a',
    this.hopM,
    this.hopS,
    this.loop = false,
    this.through,
    this.lineStatus = OperatingStatus.open,
  });

  final String id;
  final List<String> stops;

  /// Defaults to the service id (one line per service).
  final String? line;
  final String op;

  /// Per-hop metres (default 1000) and seconds (default 100; null = unknown).
  final List<int>? hopM;
  final List<int?>? hopS;
  final bool loop;
  final String? through;
  final OperatingStatus lineStatus;

  String get lineId => line ?? id;
}

class Xfer {
  const Xfer(
    this.station,
    this.from,
    this.to, {
    this.walkS,
    this.walkM,
    this.stepFree,
  });

  final String station;
  final String from;
  final String to;
  final int? walkS;
  final int? walkM;
  final bool? stepFree;
}

class Walk {
  const Walk(
    this.id,
    this.from,
    this.to,
    this.walkS,
    this.walkM, {
    this.exit = false,
  });

  final String id;
  final String from;
  final String to;
  final int walkS;
  final int walkM;
  final bool exit;
}

MetroSnapshot buildNet(
  List<Svc> specs, {
  List<Xfer> transfers = const [],
  List<Walk> walks = const [],
  Set<String> closed = const {},
  Map<String, String> fareSystemOfOperator = const {},
  List<FareSystem> fareSystems = const [],
  List<FareSlab> slabs = const [],
  List<FareDiscount> discounts = const [],
  List<FareOverride> overrides = const [],
  List<Timing> timings = const [],
}) {
  final ids = <String>[];
  for (final s in specs) {
    for (final st in s.stops) {
      if (!ids.contains(st)) ids.add(st);
    }
  }
  final stations = [
    for (var i = 0; i < ids.length; i++)
      Station(
        id: ids[i],
        nameEn: 'TEST ${ids[i]}',
        lat: 28.5 + i * 0.001,
        lng: 77.1,
        status: closed.contains(ids[i])
            ? OperatingStatus.closed
            : OperatingStatus.open,
        provenance: prov,
      ),
  ];
  final lineIds = <String>[];
  final lines = <Line>[];
  final services = <LineService>[];
  final stops = <ServiceStop>[];
  final edges = <Edge>[];
  final stationLines = <StationLine>[];
  for (final s in specs) {
    if (!lineIds.contains(s.lineId)) {
      lineIds.add(s.lineId);
      lines.add(
        Line(
          id: s.lineId,
          operatorId: s.op,
          nameEn: 'TEST ${s.lineId}',
          colorHex: '#112233',
          textColorHex: '#FFFFFF',
          sort: lineIds.length,
          status: s.lineStatus,
        ),
      );
    }
    services.add(
      LineService(
        id: s.id,
        lineId: s.lineId,
        name: s.id,
        isLoop: s.loop,
        throughServiceOf: s.through,
      ),
    );
    var dist = 0;
    for (var i = 0; i < s.stops.length; i++) {
      stops.add(
        ServiceStop(
          serviceId: s.id,
          seq: i,
          stationId: s.stops[i],
          distFromStartM: dist,
        ),
      );
      stationLines.add(StationLine(stationId: s.stops[i], lineId: s.lineId));
      if (i + 1 < s.stops.length) dist += s.hopM?[i] ?? 1000;
    }
    final hops = s.stops.length - 1 + (s.loop ? 1 : 0);
    for (var i = 0; i < hops; i++) {
      final a = s.stops[i];
      final b = s.stops[(i + 1) % s.stops.length];
      final m = s.hopM != null && i < s.hopM!.length ? s.hopM![i] : 1000;
      final t = s.hopS != null && i < s.hopS!.length ? s.hopS![i] : 100;
      for (final (x, y) in [(a, b), (b, a)]) {
        edges.add(
          Edge(
            id: '${s.id}:$x>$y',
            serviceId: s.id,
            fromStation: x,
            toStation: y,
            distanceM: m,
            travelS: t,
            provenance: prov,
          ),
        );
      }
    }
  }
  final operatorIds = {for (final s in specs) s.op};
  return MetroSnapshot(
    meta: const {
      MetaKeys.datasetVersion: '2026.10.0',
      MetaKeys.schemaVersion: '1',
      MetaKeys.builtAt: '2026-10-05T00:00:00Z',
      MetaKeys.city: 'testville',
      MetaKeys.attribution: 'TEST DATA',
      MetaKeys.bbox: '27.3,76.0,29.3,78.7',
      MetaKeys.isTestData: 'true',
    },
    operators: [
      for (final o in operatorIds.toList()..sort())
        Operator(
          id: o,
          nameEn: 'TEST $o',
          fareSystemId: fareSystemOfOperator[o],
        ),
    ],
    lines: lines,
    services: services,
    serviceStops: stops,
    stations: stations,
    stationLines: stationLines,
    edges: edges,
    transfers: [
      for (final t in transfers)
        Transfer(
          stationId: t.station,
          fromLine: t.from,
          toLine: t.to,
          walkS: t.walkS,
          walkM: t.walkM,
          stepFree: t.stepFree,
          provenance: prov,
        ),
    ],
    walkLinks: [
      for (final w in walks)
        WalkLink(
          id: w.id,
          fromStation: w.from,
          toStation: w.to,
          walkM: w.walkM,
          walkS: w.walkS,
          requiresExit: w.exit,
          provenance: prov,
        ),
    ],
    fareSystems: fareSystems,
    fareSlabs: slabs,
    fareDiscounts: discounts,
    fareOverrides: overrides,
    timings: timings,
  );
}

/// A symmetric two-line cross: red a-b-c-d-e and blue x-c-y meeting at c.
/// Every hop is 1000 m / 100 s; the interchange walk is 60 s / 50 m.
MetroSnapshot crossNet({int? walkS = 60, int? walkM = 50}) => buildNet(
  const [
    Svc('red', ['a', 'b', 'c', 'd', 'e']),
    Svc('blue', ['x', 'c', 'y']),
  ],
  transfers: [
    Xfer('c', 'red', 'blue', walkS: walkS, walkM: walkM, stepFree: true),
    Xfer('c', 'blue', 'red', walkS: walkS, walkM: walkM, stepFree: true),
  ],
);

/// Itinerary summary used in expectations: `R:a>c|T:c|R:c>y`.
String shape(Itinerary it) => [
  for (final l in it.legs)
    switch (l) {
      RideLeg() => 'R:${l.stationIds.join('>')}',
      TransferLeg() => 'T:${l.stationId}',
      WalkLeg() => 'W:${l.fromStationId}>${l.toStationId}',
    },
].join('|');
