import 'package:metro_core/metro_core.dart' hide Platform;

/// Invented TEST DATA for app tests. Nothing here describes a real network;
/// names are made up and never come from the real dataset.
const testProvenance = Provenance(
  sourceId: 'test-fixture',
  confidence: Confidence.community,
);

class TStation {
  const TStation(
    this.id,
    this.en, {
    this.hi,
    this.codes = const {},
    this.aliases = const [],
    this.status = OperatingStatus.open,
  });

  final String id;
  final String en;

  /// null = the dataset has no Hindi name.
  final String? hi;

  /// line id -> station code
  final Map<String, String> codes;
  final List<String> aliases;
  final OperatingStatus status;
}

class TService {
  const TService(
    this.id,
    this.line,
    this.stops, {
    this.op = 'op-a',
    this.hopS,
    this.hopM,
  });

  final String id;
  final String line;
  final List<String> stops;
  final String op;

  /// seconds per hop; null entries / null list = unknown (estimated).
  final List<int?>? hopS;
  final List<int>? hopM;
}

const _lineNames = <String, (String, String?, String, String)>{
  // id: (name_en, name_hi, colour, text colour)
  'red': ('Test Red Line', 'टेस्ट लाल लाइन', '#C62828', '#FFFFFF'),
  'blue': ('Test Blue Line', null, '#1565C0', '#FFFFFF'),
  'ring': ('Test Ring Line', 'टेस्ट रिंग लाइन', '#AD1457', '#FFFFFF'),
  'green': ('Test Green Line', 'टेस्ट हरी लाइन', '#2E7D32', '#FFFFFF'),
  'island': ('Test Island Line', null, '#F9A825', '#000000'),
  'slow': ('Test Slow Line', null, '#6D4C41', '#FFFFFF'),
  'f1': ('Test F1', null, '#00838F', '#FFFFFF'),
  'f2': ('Test F2', null, '#4527A0', '#FFFFFF'),
  'f3': ('Test F3', null, '#EF6C00', '#FFFFFF'),
};

MetroSnapshot buildTestNetwork({
  required List<TStation> stations,
  required List<TService> services,
  List<(String, String, String, int?, int?)> transfers = const [],
  List<(String, String, String, int, int, bool)> walks = const [],
  bool fares = true,
  bool draft = false,
  bool testData = true,
}) {
  final lineIds = <String>[];
  final lines = <Line>[];
  for (final s in services) {
    if (lineIds.contains(s.line)) continue;
    lineIds.add(s.line);
    final n = _lineNames[s.line]!;
    lines.add(
      Line(
        id: s.line,
        operatorId: s.op,
        nameEn: n.$1,
        nameHi: n.$2,
        colorHex: n.$3,
        textColorHex: n.$4,
        sort: lineIds.length,
        status: OperatingStatus.open,
      ),
    );
  }
  final edges = <Edge>[];
  final stops = <ServiceStop>[];
  final stationLines = <StationLine>[];
  final byId = {for (final s in stations) s.id: s};
  for (final s in services) {
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
      final code = byId[s.stops[i]]?.codes[s.line];
      if (!stationLines.any(
        (x) => x.stationId == s.stops[i] && x.lineId == s.line,
      )) {
        stationLines.add(
          StationLine(
            stationId: s.stops[i],
            lineId: s.line,
            stationCode: code,
          ),
        );
      }
      if (i + 1 < s.stops.length) {
        final m = s.hopM != null && i < s.hopM!.length ? s.hopM![i] : 1000;
        final t = s.hopS == null
            ? 100
            : (i < s.hopS!.length ? s.hopS![i] : 100);
        dist += m;
        for (final (a, b) in [
          (s.stops[i], s.stops[i + 1]),
          (s.stops[i + 1], s.stops[i]),
        ]) {
          edges.add(
            Edge(
              id: '${s.id}:$a>$b',
              serviceId: s.id,
              fromStation: a,
              toStation: b,
              distanceM: m,
              travelS: t,
              provenance: testProvenance,
            ),
          );
        }
      }
    }
  }
  final operators = {for (final s in services) s.op}.toList()..sort();
  return MetroSnapshot(
    meta: {
      MetaKeys.datasetVersion: '2026.10.0',
      MetaKeys.schemaVersion: '$currentSchemaVersion',
      MetaKeys.builtAt: '2026-10-05T00:00:00Z',
      MetaKeys.city: 'testville',
      MetaKeys.attribution: 'TEST DATA - invented for tests',
      MetaKeys.bbox: '27.3,76.0,29.3,78.7',
      if (testData) MetaKeys.isTestData: 'true',
      if (draft) MetaKeys.stage: 'draft',
    },
    operators: [
      for (final o in operators)
        Operator(
          id: o,
          nameEn: 'Test $o',
          fareSystemId: fares && o == 'op-a' ? 'fs-a' : null,
        ),
    ],
    lines: lines,
    services: [
      for (final s in services)
        LineService(id: s.id, lineId: s.line, name: s.id),
    ],
    serviceStops: stops,
    stations: [
      for (var i = 0; i < stations.length; i++)
        Station(
          id: stations[i].id,
          nameEn: stations[i].en,
          nameHi: stations[i].hi,
          lat: 28.5 + i * 0.001,
          lng: 77.1,
          status: stations[i].status,
          provenance: testProvenance,
        ),
    ],
    stationNames: [
      for (final s in stations) ...[
        StationName(
          stationId: s.id,
          text: s.en,
          lang: 'en',
          kind: NameKind.official,
        ),
        if (s.hi != null)
          StationName(
            stationId: s.id,
            text: s.hi!,
            lang: 'hi',
            kind: NameKind.official,
          ),
        for (final a in s.aliases)
          StationName(
            stationId: s.id,
            text: a,
            lang: 'en',
            kind: NameKind.alias,
          ),
      ],
    ],
    stationLines: stationLines,
    edges: edges,
    transfers: [
      for (final t in transfers)
        Transfer(
          stationId: t.$1,
          fromLine: t.$2,
          toLine: t.$3,
          walkS: t.$4,
          walkM: t.$5,
          provenance: testProvenance,
        ),
    ],
    walkLinks: [
      for (final w in walks)
        WalkLink(
          id: 'walk-${w.$1}-${w.$2}',
          fromStation: w.$1,
          toStation: w.$2,
          walkM: w.$4,
          walkS: w.$5,
          requiresExit: w.$6,
          provenance: testProvenance,
        ),
    ],
    fareSystems: fares
        ? const [
            FareSystem(
              id: 'fs-a',
              operatorId: 'op-a',
              currency: 'INR',
              effectiveFrom: '2026-01-01',
              sourceId: 'test-fixture',
            ),
          ]
        : const [],
    fareSlabs: fares
        ? const [
            FareSlab(
              fareSystemId: 'fs-a',
              dayType: DayType.regular,
              minKm: 0,
              maxKm: 2,
              amountPaise: 1000,
            ),
            FareSlab(
              fareSystemId: 'fs-a',
              dayType: DayType.regular,
              minKm: 2,
              maxKm: 5,
              amountPaise: 2050,
            ),
            FareSlab(
              fareSystemId: 'fs-a',
              dayType: DayType.regular,
              minKm: 5,
              maxKm: null,
              amountPaise: 3000,
            ),
          ]
        : const [],
  );
}

/// The shared invented network.
///
/// red:   alpha - beta - central - delta - echo   (hop 100 s / 1000 m)
/// blue:  xray - central - yankee                 (no Hindi names for xray)
/// ring:  hub - ringa - ringb - hub - spur        (Hub visited twice)
/// green: gamma - gamut (other operator; walk link echo<->gamma, exits)
/// island: isle-a - isle-b                        (not connected to anything)
/// zulu route: slow (alpha..zulu direct, 300 s hops) vs f1/f2/f3 chain
MetroSnapshot demoNetwork({
  bool fares = true,
  bool draft = false,
  bool testData = true,
}) => buildTestNetwork(
  fares: fares,
  draft: draft,
  testData: testData,
  stations: const [
    TStation(
      'alpha',
      'Alpha Chowk',
      hi: 'अल्फा चौक',
      codes: {'red': 'AL1', 'slow': 'AL1', 'f1': 'AL1'},
    ),
    TStation('beta', 'Beta Nagar', hi: 'बीटा नगर', codes: {'red': 'BT'}),
    TStation(
      'central',
      'Central Place',
      hi: 'सेंट्रल प्लेस',
      codes: {'red': 'CP', 'blue': 'CP'},
      aliases: ['Old Central'],
    ),
    TStation('delta', 'Delta Vihar', hi: 'डेल्टा विहार'),
    TStation('echo', 'Echo Park', hi: 'इको पार्क'),
    TStation('xray', 'Xray Gate'), // no Hindi name in the data
    TStation('yankee', 'Yankee Bagh', hi: 'यांकी बाग'),
    TStation('hub', 'Hub Junction', hi: 'हब जंक्शन'),
    TStation('ringa', 'Ring Alpha'),
    TStation('ringb', 'Ring Beta'),
    TStation('spur', 'Spur End'),
    TStation('gamma', 'Gamma Colony', hi: 'गामा कॉलोनी'),
    TStation('gamut', 'Gamut Road'),
    TStation('isle-a', 'Island Alpha'),
    TStation('isle-b', 'Island Beta'),
    TStation('s1', 'Slow One'),
    TStation('s2', 'Slow Two'),
    TStation('s3', 'Slow Three'),
    TStation('p1', 'Quick Pivot'),
    TStation('p2', 'Quick Pillar'),
    TStation('zulu', 'Zulu Terminal', hi: 'ज़ुलू टर्मिनल'),
    TStation('halt', 'Halt Road', status: OperatingStatus.closed),
    TStation('twin-1', 'Twin Place', codes: {'red': 'TW'}),
    TStation('twin-2', 'Twin Place', codes: {'blue': 'TW'}),
  ],
  services: const [
    TService('red-main', 'red', [
      'alpha',
      'beta',
      'central',
      'delta',
      'echo',
      'twin-1',
    ]),
    TService('blue-main', 'blue', ['xray', 'central', 'yankee', 'twin-2']),
    TService('ring-main', 'ring', [
      'hub',
      'ringa',
      'ringb',
      'hub',
      'spur',
    ]),
    TService('green-main', 'green', ['gamma', 'gamut'], op: 'op-b'),
    TService('island-main', 'island', ['isle-a', 'isle-b']),
    TService(
      'slow-main',
      'slow',
      ['alpha', 's1', 's2', 's3', 'zulu'],
      hopS: [300, 300, 300, 300],
    ),
    TService('f1-main', 'f1', ['alpha', 'p1'], hopS: [100]),
    TService('f2-main', 'f2', ['p1', 'p2'], hopS: [100]),
    TService('f3-main', 'f3', ['p2', 'zulu'], hopS: [100]),
  ],
  transfers: const [
    ('central', 'red', 'blue', 120, 90),
    ('central', 'blue', 'red', 120, 90),
    ('p1', 'f1', 'f2', 60, 40),
    ('p1', 'f2', 'f1', 60, 40),
    ('p2', 'f2', 'f3', 60, 40),
    ('p2', 'f3', 'f2', 60, 40),
    ('alpha', 'red', 'slow', 60, 30),
    ('alpha', 'slow', 'red', 60, 30),
    ('alpha', 'red', 'f1', 60, 30),
    ('alpha', 'f1', 'red', 60, 30),
    ('alpha', 'slow', 'f1', 60, 30),
    ('alpha', 'f1', 'slow', 60, 30),
    ('zulu', 'slow', 'f3', 60, 30),
    ('zulu', 'f3', 'slow', 60, 30),
  ],
  walks: const [('echo', 'gamma', 'walk', 300, 400, true)],
);
