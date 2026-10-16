import 'package:metro_core/metro_core.dart';

import 'fixture.dart';

/// A station of a synthetic (TEST DATA) search network. Names are invented.
class SStation {
  const SStation(
    this.id,
    this.en, {
    this.hi,
    this.aliases = const [],
    this.codes = const {},
    this.popularity = 0,
    this.status = OperatingStatus.open,
  });

  final String id;
  final String en;
  final String? hi;

  /// `(text, lang, kind)`.
  final List<(String, String, NameKind)> aliases;

  /// line id -> station code.
  final Map<String, String> codes;
  final int popularity;
  final OperatingStatus status;
}

/// Alias helper.
(String, String, NameKind) alias(
  String text, {
  String lang = 'en',
  NameKind kind = NameKind.alias,
}) => (text, lang, kind);

const searchLines = <String, (String, String?, String?)>{
  // id: (name_en, name_hi, short)
  'l-red': ('TEST Red Line', 'टेस्ट लाल लाइन', 'TR'),
  'l-blue': ('TEST Blue Line', null, 'TB'),
  'l-gone': ('TEST Old Line', null, null),
};

/// Builds a snapshot for search tests: every station is on the lines named in
/// its `codes` (or on `l-red` when it has none).
MetroSnapshot buildSearchNet(
  List<SStation> list, {
  Map<String, String> meta = const {},
}) {
  final lines = <Line>[];
  var sort = 0;
  for (final e in searchLines.entries) {
    lines.add(
      Line(
        id: e.key,
        operatorId: 'op',
        nameEn: e.value.$1,
        nameHi: e.value.$2,
        shortName: e.value.$3,
        colorHex: '#112233',
        textColorHex: '#FFFFFF',
        sort: ++sort,
        status: e.key == 'l-gone'
            ? OperatingStatus.closed
            : OperatingStatus.open,
      ),
    );
  }
  final stations = <Station>[];
  final names = <StationName>[];
  final stationLines = <StationLine>[];
  final services = <LineService>[
    for (final l in searchLines.keys)
      LineService(id: '$l-svc', lineId: l, name: '$l-svc'),
  ];
  final stops = <ServiceStop>[];
  final seq = <String, int>{};
  for (final s in list) {
    stations.add(
      Station(
        id: s.id,
        nameEn: s.en,
        nameHi: s.hi,
        lat: 28.5 + stations.length * 0.001,
        lng: 77.1,
        popularity: s.popularity,
        status: s.status,
        provenance: prov,
      ),
    );
    names.add(
      StationName(
        stationId: s.id,
        text: s.en,
        lang: 'en',
        kind: NameKind.official,
      ),
    );
    if (s.hi != null) {
      names.add(
        StationName(
          stationId: s.id,
          text: s.hi!,
          lang: 'hi',
          kind: NameKind.official,
        ),
      );
    }
    for (final a in s.aliases) {
      names.add(
        StationName(stationId: s.id, text: a.$1, lang: a.$2, kind: a.$3),
      );
    }
    final lineIds = s.codes.isEmpty ? ['l-red'] : s.codes.keys.toList();
    for (final l in lineIds) {
      stationLines.add(
        StationLine(stationId: s.id, lineId: l, stationCode: s.codes[l]),
      );
      final n = seq[l] = (seq[l] ?? -1) + 1;
      stops.add(
        ServiceStop(
          serviceId: '$l-svc',
          seq: n,
          stationId: s.id,
          distFromStartM: n * 1000,
        ),
      );
    }
  }
  return MetroSnapshot(
    meta: {
      MetaKeys.datasetVersion: '2026.10.0',
      MetaKeys.schemaVersion: '1',
      MetaKeys.builtAt: '2026-10-05T00:00:00Z',
      MetaKeys.city: 'testville',
      MetaKeys.attribution: 'TEST DATA',
      MetaKeys.bbox: '27.3,76.0,29.3,78.7',
      MetaKeys.isTestData: 'true',
      ...meta,
    },
    lines: lines,
    services: services,
    serviceStops: stops,
    stations: stations,
    stationNames: names,
    stationLines: stationLines,
  );
}

/// The shared synthetic network used by most search tests. Every name is
/// invented; spelling patterns mimic real ones (Hindi spellings, dotted
/// abbreviations, roman numerals, "Sector N", Hindi names that are missing).
final searchStations = <SStation>[
  const SStation(
    'raghav-chowk',
    'Raghav Chowk',
    hi: 'राघव चौक',
    codes: {'l-red': 'RGV', 'l-blue': 'RGV'},
    popularity: 40,
  ),
  const SStation(
    'kamla-gate',
    'Kamla Gate',
    hi: 'कमला गेट',
    codes: {'l-red': 'KMG'},
    aliases: [
      ('Old Kamla', 'en', NameKind.old),
      ('Kamla Gat', 'en', NameKind.misspelling),
    ],
  ),
  const SStation('kamal', 'Kamal', hi: 'कमल'),
  const SStation('kamal-nagar', 'Kamal Nagar', hi: 'कमल नगर'),
  const SStation('kamal-nagar-ext', 'Kamal Nagar Extension'),
  const SStation('nagar-kamal-park', 'Nagar Kamal Park', hi: 'नगर कमल पार्क'),
  SStation(
    'zed-square',
    'Zed Square',
    aliases: [alias('Kamal')],
    codes: const {'l-blue': 'ZED'},
  ),
  const SStation(
    'jor-nagar',
    'Jor Nagar',
    hi: 'जोर नगर',
    codes: {'l-blue': 'JRN'},
  ),
  const SStation('sundar-nagar', 'Sundar Nagar', hi: 'सुंदर नगर'),
  const SStation('vihar-sector-9', 'Vihar Sector 9', hi: 'विहार सेक्टर ९'),
  const SStation('vihar-sector-21', 'Vihar Sector 21', hi: 'विहार सेक्टर 21'),
  const SStation('mayur-kunj-i', 'Mayur Kunj - I', hi: 'मयूर कुंज - १'),
  const SStation('mayur-kunj-ii', 'Mayur Kunj - II'),
  const SStation(
    'n-k-s-p',
    'N.K.S.P.',
    hi: 'एन.के.एस.पी.',
    codes: {'l-red': 'NKSP'},
  ),
  const SStation('orchid-park', 'Orchid Park'), // no Hindi name in the data
  SStation(
    'ifko-chowk',
    'Ifko Chowk',
    hi: 'इफ़को चौक',
    aliases: [alias('इफ्को चौक', lang: 'hi')],
  ),
  const SStation('anand-bagh', 'Anand Bagh', hi: 'आनंद बाग'),
  const SStation('lakshmi-nagar', 'Lakshmi Nagar', hi: 'लक्ष्मी नगर'),
  SStation(
    'laxmi-nagar',
    'Laxmi Nagar',
    hi: 'लक्ष्मी नगर',
    aliases: [
      alias('Lakshmi Nagar'),
      alias('Landmark Mall', kind: NameKind.landmark),
    ],
  ),
  const SStation(
    'closed-halt',
    'Closed Halt',
    status: OperatingStatus.closed,
  ),
  const SStation('uttam-nagar-east', 'Uttam Nagar East', hi: 'उत्तम नगर ईस्ट'),
  const SStation('uttam-nagar-west', 'Uttam Nagar West', hi: 'उत्तम नगर वेस्ट'),
  const SStation('jorbagh-hall', 'Jor Bagh Hall'),
];

MetroSnapshot searchNet() => buildSearchNet(searchStations);
