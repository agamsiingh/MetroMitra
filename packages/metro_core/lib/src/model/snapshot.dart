import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/fare.dart';
import 'package:metro_core/src/model/network.dart';
import 'package:metro_core/src/model/provenance.dart';
import 'package:metro_core/src/model/station_facts.dart';

/// Keys of the `meta` table.
abstract final class MetaKeys {
  static const datasetVersion = 'dataset_version';
  static const schemaVersion = 'schema_version';
  static const builtAt = 'built_at';
  static const city = 'city';
  static const attribution = 'attribution';

  /// `minLat,minLng,maxLat,maxLng` - coordinates outside are rejected.
  static const bbox = 'bbox';

  /// `true` for synthetic test fixtures; must never ship to users.
  static const isTestData = 'is_test_data';

  /// `draft` (built by the pipeline with known gaps; never shipped) or
  /// `release`. Absent = release.
  static const stage = 'stage';

  static const required = [
    datasetVersion,
    schemaVersion,
    builtAt,
    city,
    attribution,
    bbox,
  ];
}

/// Immutable in-memory copy of one dataset. Pure data + id lookups; routing,
/// search and fare engines are built *from* it in later milestones.
class MetroSnapshot {
  MetroSnapshot({
    required this.meta,
    this.sources = const [],
    this.operators = const [],
    this.lines = const [],
    this.services = const [],
    this.serviceStops = const [],
    this.stations = const [],
    this.stationNames = const [],
    this.stationLines = const [],
    this.edges = const [],
    this.transfers = const [],
    this.walkLinks = const [],
    this.platforms = const [],
    this.gates = const [],
    this.gateLandmarks = const [],
    this.facilities = const [],
    this.accessibility = const [],
    this.fareSystems = const [],
    this.fareSlabs = const [],
    this.fareDiscounts = const [],
    this.fareOverrides = const [],
    this.timings = const [],
    this.origins = const [],
  });

  final Map<String, String> meta;
  final List<Source> sources;
  final List<Operator> operators;
  final List<Line> lines;
  final List<LineService> services;
  final List<ServiceStop> serviceStops;
  final List<Station> stations;
  final List<StationName> stationNames;
  final List<StationLine> stationLines;
  final List<Edge> edges;
  final List<Transfer> transfers;
  final List<WalkLink> walkLinks;
  final List<Platform> platforms;
  final List<Gate> gates;
  final List<GateLandmark> gateLandmarks;
  final List<Facility> facilities;
  final List<Accessibility> accessibility;
  final List<FareSystem> fareSystems;
  final List<FareSlab> fareSlabs;
  final List<FareDiscount> fareDiscounts;
  final List<FareOverride> fareOverrides;
  final List<Timing> timings;
  final List<Origin> origins;

  /// Copy with some tables replaced (tests and the pipeline's merge step).
  MetroSnapshot copyWith({
    Map<String, String>? meta,
    List<Source>? sources,
    List<Operator>? operators,
    List<Line>? lines,
    List<LineService>? services,
    List<ServiceStop>? serviceStops,
    List<Station>? stations,
    List<StationName>? stationNames,
    List<StationLine>? stationLines,
    List<Edge>? edges,
    List<Transfer>? transfers,
    List<WalkLink>? walkLinks,
    List<Platform>? platforms,
    List<Gate>? gates,
    List<GateLandmark>? gateLandmarks,
    List<Facility>? facilities,
    List<Accessibility>? accessibility,
    List<FareSystem>? fareSystems,
    List<FareSlab>? fareSlabs,
    List<FareDiscount>? fareDiscounts,
    List<FareOverride>? fareOverrides,
    List<Timing>? timings,
    List<Origin>? origins,
  }) => MetroSnapshot(
    meta: meta ?? this.meta,
    sources: sources ?? this.sources,
    operators: operators ?? this.operators,
    lines: lines ?? this.lines,
    services: services ?? this.services,
    serviceStops: serviceStops ?? this.serviceStops,
    stations: stations ?? this.stations,
    stationNames: stationNames ?? this.stationNames,
    stationLines: stationLines ?? this.stationLines,
    edges: edges ?? this.edges,
    transfers: transfers ?? this.transfers,
    walkLinks: walkLinks ?? this.walkLinks,
    platforms: platforms ?? this.platforms,
    gates: gates ?? this.gates,
    gateLandmarks: gateLandmarks ?? this.gateLandmarks,
    facilities: facilities ?? this.facilities,
    accessibility: accessibility ?? this.accessibility,
    fareSystems: fareSystems ?? this.fareSystems,
    fareSlabs: fareSlabs ?? this.fareSlabs,
    fareDiscounts: fareDiscounts ?? this.fareDiscounts,
    fareOverrides: fareOverrides ?? this.fareOverrides,
    timings: timings ?? this.timings,
    origins: origins ?? this.origins,
  );

  String? get datasetVersion => meta[MetaKeys.datasetVersion];
  int? get schemaVersion => int.tryParse(meta[MetaKeys.schemaVersion] ?? '');
  String? get city => meta[MetaKeys.city];
  bool get isTestData => meta[MetaKeys.isTestData] == 'true';
  bool get isDraft => meta[MetaKeys.stage] == 'draft';

  late final Map<String, Station> _stationsById = {
    for (final s in stations) s.id: s,
  };
  late final Map<String, Line> _linesById = {for (final l in lines) l.id: l};
  late final Map<String, LineService> _servicesById = {
    for (final s in services) s.id: s,
  };

  Station? station(String id) => _stationsById[id];
  Line? line(String id) => _linesById[id];
  LineService? service(String id) => _servicesById[id];

  /// Stops of a service in travel order.
  List<ServiceStop> stopsOf(String serviceId) =>
      (serviceStops.where((s) => s.serviceId == serviceId).toList()
        ..sort((a, b) => a.seq.compareTo(b.seq)));

  List<LineService> servicesOfLine(String lineId) =>
      services.where((s) => s.lineId == lineId).toList();

  /// Lines serving a station (from `station_line`).
  List<Line> linesAt(String stationId) => [
    for (final sl in stationLines)
      if (sl.stationId == stationId) ?line(sl.lineId),
  ];

  /// All names (official, aliases, old, misspellings, landmarks) of a station.
  List<StationName> namesOf(String stationId) =>
      stationNames.where((n) => n.stationId == stationId).toList();

  List<Gate> gatesAt(String stationId) =>
      gates.where((g) => g.stationId == stationId).toList();

  List<GateLandmark> landmarksOf(String gateId) =>
      gateLandmarks.where((l) => l.gateId == gateId).toList();

  List<Platform> platformsAt(String stationId) =>
      platforms.where((p) => p.stationId == stationId).toList();

  List<Facility> facilitiesAt(String stationId) =>
      facilities.where((f) => f.stationId == stationId).toList();

  /// null = no accessibility record (unknown), not "inaccessible".
  Accessibility? accessibilityAt(String stationId) {
    for (final a in accessibility) {
      if (a.stationId == stationId) return a;
    }
    return null;
  }

  List<Transfer> transfersAt(String stationId) =>
      transfers.where((t) => t.stationId == stationId).toList();

  List<Edge> edgesFrom(String stationId) =>
      edges.where((e) => e.fromStation == stationId).toList();

  List<WalkLink> walkLinksOf(String stationId) => walkLinks
      .where((w) => w.fromStation == stationId || w.toStation == stationId)
      .toList();

  List<Timing> timingsAt(String stationId) =>
      timings.where((t) => t.stationId == stationId).toList();

  FareSystem? fareSystemOf(String operatorId) {
    for (final f in fareSystems) {
      if (f.operatorId == operatorId) return f;
    }
    return null;
  }

  /// Whether a fact may be shown as verified without a caveat.
  static bool isTrusted(Provenance p) =>
      p.confidence == Confidence.official ||
      p.confidence == Confidence.verified;
}
