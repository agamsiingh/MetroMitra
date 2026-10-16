import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/provenance.dart';

class Operator {
  const Operator({
    required this.id,
    required this.nameEn,
    this.nameHi,
    this.fareSystemId,
  });

  final String id;
  final String nameEn;

  /// null = unknown (never transliterated or guessed).
  final String? nameHi;

  /// null = fares not (yet) modelled for this operator.
  final String? fareSystemId;
}

class Line {
  const Line({
    required this.id,
    required this.operatorId,
    required this.nameEn,
    required this.colorHex,
    required this.textColorHex,
    required this.sort,
    required this.status,
    this.nameHi,
    this.shortName,
  });

  final String id;
  final String operatorId;
  final String nameEn;
  final String? nameHi;
  final String? shortName;

  /// `#RRGGBB`. Line colours are data, never theme tokens.
  final String colorHex;
  final String textColorHex;
  final int sort;
  final OperatingStatus status;
}

/// A runnable pattern on a line: a branch, a loop or a through-running service.
class LineService {
  const LineService({
    required this.id,
    required this.lineId,
    required this.name,
    this.isLoop = false,
    this.throughServiceOf,
  });

  final String id;
  final String lineId;
  final String name;
  final bool isLoop;

  /// Service this one continues into without a change of train.
  final String? throughServiceOf;
}

class ServiceStop {
  const ServiceStop({
    required this.serviceId,
    required this.seq,
    required this.stationId,
    required this.distFromStartM,
  });

  final String serviceId;
  final int seq;
  final String stationId;
  final int distFromStartM;
}

class Station {
  const Station({
    required this.id,
    required this.nameEn,
    required this.lat,
    required this.lng,
    required this.status,
    required this.provenance,
    this.nameHi,
    this.popularity = 0,
    this.openedOn,
    this.mapX,
    this.mapY,
  });

  final String id;
  final String nameEn;
  final String? nameHi;
  final double lat;
  final double lng;
  final int popularity;
  final OperatingStatus status;
  final String? openedOn;

  /// Schematic map position (docs/map.md); both null until the map milestone.
  final double? mapX;
  final double? mapY;
  final Provenance provenance;
}

class StationName {
  const StationName({
    required this.stationId,
    required this.text,
    required this.lang,
    required this.kind,
  });

  final String stationId;
  final String text;

  /// `en` or `hi`.
  final String lang;
  final NameKind kind;
}

class StationLine {
  const StationLine({
    required this.stationId,
    required this.lineId,
    this.stationCode,
  });

  final String stationId;
  final String lineId;
  final String? stationCode;
}

/// Directed connection between two consecutive stops of a service.
/// Both directions are stored; `travelS` includes dwell.
class Edge {
  const Edge({
    required this.id,
    required this.serviceId,
    required this.fromStation,
    required this.toStation,
    required this.distanceM,
    required this.provenance,
    this.travelS,
  });

  final String id;
  final String serviceId;
  final String fromStation;
  final String toStation;

  /// null = unknown. Travel times are never invented; see ADR-027.
  final int? travelS;
  final int distanceM;
  final Provenance provenance;
}

/// In-station interchange between two lines.
class Transfer {
  const Transfer({
    required this.stationId,
    required this.fromLine,
    required this.toLine,
    required this.provenance,
    this.walkM,
    this.walkS,
    this.stepFree,
    this.notesEn,
    this.notesHi,
  });

  final String stationId;
  final String fromLine;
  final String toLine;

  /// null = interchange exists but walking distance/time is unknown.
  final int? walkM;
  final int? walkS;

  /// null = unknown (never assume).
  final bool? stepFree;
  final String? notesEn;
  final String? notesHi;
  final Provenance provenance;
}

/// Out-of-system walk (e.g. between separate operators' stations).
class WalkLink {
  const WalkLink({
    required this.id,
    required this.fromStation,
    required this.toStation,
    required this.walkM,
    required this.walkS,
    required this.requiresExit,
    required this.provenance,
    this.stepFree,
    this.notesEn,
    this.notesHi,
  });

  final String id;
  final String fromStation;
  final String toStation;
  final int walkM;
  final int walkS;

  /// true = leave the paid area (separate ticket likely).
  final bool requiresExit;
  final bool? stepFree;
  final String? notesEn;
  final String? notesHi;
  final Provenance provenance;
}
