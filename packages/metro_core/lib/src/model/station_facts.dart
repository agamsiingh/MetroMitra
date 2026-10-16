import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/provenance.dart';

/// Platform at a station for a line/direction. `number` is text ("1", "2A").
class Platform {
  const Platform({
    required this.stationId,
    required this.lineId,
    required this.number,
    required this.provenance,
    this.towardsStationId,
    this.serviceId,
    this.notesEn,
    this.notesHi,
  });

  final String stationId;
  final String lineId;
  final String number;
  final String? towardsStationId;
  final String? serviceId;
  final String? notesEn;
  final String? notesHi;
  final Provenance provenance;
}

/// Station entry/exit gate. Boolean features are nullable: null = unknown,
/// which the UI/assistant must say rather than guess.
class Gate {
  const Gate({
    required this.id,
    required this.stationId,
    required this.number,
    required this.provenance,
    this.nameEn,
    this.nameHi,
    this.lat,
    this.lng,
    this.isOpen,
    this.hasLift,
    this.hasRamp,
    this.hasEscalator,
    this.isStepFree,
  });

  /// `<station-id>:g<number>`.
  final String id;
  final String stationId;
  final int number;
  final String? nameEn;
  final String? nameHi;
  final double? lat;
  final double? lng;
  final bool? isOpen;
  final bool? hasLift;
  final bool? hasRamp;
  final bool? hasEscalator;
  final bool? isStepFree;
  final Provenance provenance;
}

class GateLandmark {
  const GateLandmark({
    required this.gateId,
    required this.textEn,
    required this.kind,
    this.textHi,
  });

  final String gateId;
  final String textEn;
  final String? textHi;
  final GateLandmarkKind kind;
}

class Facility {
  const Facility({
    required this.stationId,
    required this.type,
    required this.provenance,
    this.gateId,
    this.locationEn,
    this.locationHi,
  });

  final String stationId;
  final FacilityType type;
  final String? gateId;
  final String? locationEn;
  final String? locationHi;
  final Provenance provenance;
}

/// Accessibility summary per station. Counts/flags are nullable = unknown.
class Accessibility {
  const Accessibility({
    required this.stationId,
    required this.provenance,
    this.lifts,
    this.escalators,
    this.tactilePath,
    this.wheelchairAvailable,
    this.notesEn,
    this.notesHi,
  });

  final String stationId;
  final int? lifts;
  final int? escalators;
  final bool? tactilePath;
  final bool? wheelchairAvailable;
  final String? notesEn;
  final String? notesHi;
  final Provenance provenance;
}

/// First/last departure for a service at a station towards a terminal.
/// Times are minutes since 00:00 of the service day (may exceed 1440).
class Timing {
  const Timing({
    required this.serviceId,
    required this.stationId,
    required this.directionTerminalId,
    required this.dayType,
    required this.firstDep,
    required this.lastDep,
    required this.provenance,
  });

  final String serviceId;
  final String stationId;
  final String directionTerminalId;
  final DayType dayType;
  final int firstDep;
  final int lastDep;
  final Provenance provenance;
}
