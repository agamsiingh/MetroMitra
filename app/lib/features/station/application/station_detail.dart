import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/features/go/application/station_options.dart';

/// What the dataset says about one station, ready to display. Built only
/// from a canonical station id. Anything the dataset does not say is null or
/// empty here, and the screen says "not in the data" rather than guessing.
class StationDetail {
  const StationDetail({
    required this.id,
    required this.nameEn,
    required this.status,
    required this.lines,
    required this.services,
    required this.aliases,
    required this.isInterchange,
    required this.provenance,
    required this.platforms,
    required this.gates,
    required this.facilities,
    this.nameHi,
    this.lat,
    this.lng,
    this.accessibility,
  });

  final String id;
  final String nameEn;
  final String? nameHi;
  final OperatingStatus status;

  /// Lines with the station code on each (null code = none in the data).
  final List<LineChipData> lines;

  /// Services stopping here, as named by the dataset.
  final List<StationService> services;

  /// Non-official names: aliases, old names, misspellings, landmarks.
  final List<StationAlias> aliases;
  final bool isInterchange;

  /// Null when the stored coordinates are unusable (never shown as a place).
  final double? lat;
  final double? lng;
  final Provenance provenance;

  final List<PlatformFact> platforms;
  final List<GateFact> gates;
  final List<FacilityFact> facilities;
  final Accessibility? accessibility;

  bool get hasCoordinates => lat != null && lng != null;
  bool get isOpen => status == OperatingStatus.open;
}

class StationService {
  const StationService({
    required this.id,
    required this.name,
    required this.lineId,
  });

  final String id;
  final String name;
  final String lineId;
}

class StationAlias {
  const StationAlias({required this.text, required this.kind});

  final String text;
  final NameKind kind;
}

class PlatformFact {
  const PlatformFact({
    required this.lineId,
    required this.number,
    this.towardsId,
  });

  final String lineId;
  final String number;
  final String? towardsId;
}

class GateFact {
  const GateFact({
    required this.number,
    this.nameEn,
    this.nameHi,
    this.hasLift,
    this.hasRamp,
    this.hasEscalator,
    this.isStepFree,
    this.isOpen,
    this.landmarks = const [],
  });

  final int number;
  final String? nameEn;
  final String? nameHi;
  final bool? hasLift;
  final bool? hasRamp;
  final bool? hasEscalator;
  final bool? isStepFree;
  final bool? isOpen;
  final List<String> landmarks;
}

class FacilityFact {
  const FacilityFact({required this.type, this.locationEn, this.locationHi});

  final FacilityType type;
  final String? locationEn;
  final String? locationHi;
}

/// The detail of [id], or null when the dataset has no such station (a name
/// or any other text is never accepted in place of an id).
StationDetail? stationDetailFor(MetroServices services, String id) {
  final snap = services.snapshot;
  final s = snap.station(id);
  if (s == null) return null;
  final option = stationOptionFor(services, id)!;
  final codes = {
    for (final sl in snap.stationLines)
      if (sl.stationId == id) sl.lineId: sl.stationCode,
  };
  final stopServices = {
    for (final st in snap.serviceStops)
      if (st.stationId == id) st.serviceId,
  };
  final validPoint = isValidCoordinate(s.lat, s.lng);
  return StationDetail(
    id: s.id,
    nameEn: s.nameEn,
    nameHi: s.nameHi,
    status: s.status,
    isInterchange: option.isInterchange,
    provenance: s.provenance,
    lat: validPoint ? s.lat : null,
    lng: validPoint ? s.lng : null,
    lines: [
      for (final l in option.lines)
        LineChipData(
          lineId: l.lineId,
          nameEn: l.nameEn,
          nameHi: l.nameHi,
          colorHex: l.colorHex,
          textColorHex: l.textColorHex,
          code: codes[l.lineId],
        ),
    ],
    services: [
      for (final sv in snap.services)
        if (stopServices.contains(sv.id))
          StationService(id: sv.id, name: sv.name, lineId: sv.lineId),
    ],
    aliases: [
      for (final n in snap.namesOf(id))
        if (n.kind != NameKind.official)
          StationAlias(text: n.text, kind: n.kind),
    ],
    platforms: [
      for (final p in snap.platformsAt(id))
        PlatformFact(
          lineId: p.lineId,
          number: p.number,
          towardsId: p.towardsStationId,
        ),
    ],
    gates: [
      for (final g in snap.gatesAt(id))
        GateFact(
          number: g.number,
          nameEn: g.nameEn,
          nameHi: g.nameHi,
          hasLift: g.hasLift,
          hasRamp: g.hasRamp,
          hasEscalator: g.hasEscalator,
          isStepFree: g.isStepFree,
          isOpen: g.isOpen,
          landmarks: [for (final l in snap.landmarksOf(g.id)) l.textEn],
        ),
    ],
    facilities: [
      for (final f in snap.facilitiesAt(id))
        FacilityFact(
          type: f.type,
          locationEn: f.locationEn,
          locationHi: f.locationHi,
        ),
    ],
    accessibility: snap.accessibilityAt(id),
  );
}
