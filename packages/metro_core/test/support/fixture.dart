import 'package:metro_core/metro_core.dart';

/// The synthetic TEST DATA network (data/fixtures/mini_network). Relative to
/// the package root, which is the working directory of `dart test`.
const fixturePath = '../../data/fixtures/mini_network/dataset.yaml';

MetroSnapshot loadFixture() => YamlDatasetLoader.loadFile(fixturePath);

/// Returns [list] with every element matching [test] replaced by [change].
List<T> replaceWhere<T>(
  List<T> list,
  bool Function(T) test,
  T Function(T) change,
) => [for (final x in list) test(x) ? change(x) : x];

const prov = Provenance(
  sourceId: 'test-fixture',
  confidence: Confidence.community,
);

Station stationWith(
  Station s, {
  String? id,
  String? nameHi,
  double? lat,
  double? lng,
  Provenance? provenance,
  double? mapX,
}) => Station(
  id: id ?? s.id,
  nameEn: s.nameEn,
  nameHi: nameHi ?? s.nameHi,
  lat: lat ?? s.lat,
  lng: lng ?? s.lng,
  popularity: s.popularity,
  status: s.status,
  openedOn: s.openedOn,
  mapX: mapX ?? s.mapX,
  mapY: s.mapY,
  provenance: provenance ?? s.provenance,
);

Edge edgeWith(
  Edge e, {
  String? id,
  String? to,
  int? travelS,
  int? distanceM,
}) => Edge(
  id: id ?? e.id,
  serviceId: e.serviceId,
  fromStation: e.fromStation,
  toStation: to ?? e.toStation,
  travelS: travelS ?? e.travelS,
  distanceM: distanceM ?? e.distanceM,
  provenance: e.provenance,
);

ServiceStop stopWith(ServiceStop s, {int? seq, String? stationId, int? dist}) =>
    ServiceStop(
      serviceId: s.serviceId,
      seq: seq ?? s.seq,
      stationId: stationId ?? s.stationId,
      distFromStartM: dist ?? s.distFromStartM,
    );
