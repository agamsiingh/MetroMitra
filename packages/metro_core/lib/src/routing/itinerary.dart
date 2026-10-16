import 'package:metro_core/src/fare/fare_quote.dart';
import 'package:metro_core/src/model/provenance.dart';

/// Cost ordering used to pick a route (docs/routing.md). Each profile compares
/// (time, changes, walk, stops) in a different priority order.
enum RoutingProfile {
  fastest,
  easiest,
  lessWalking,
  fewestStops,
}

/// Why the rider changes trains at a station.
enum TransferKind {
  /// Different lines; walk data comes from a `transfer` row.
  lineChange,

  /// Different services of one line (e.g. branch and main). The dataset has no
  /// row for these, so the walk is a fallback estimate.
  sameLineChange,

  /// The same service visits the station twice (ring + spur); the rider must
  /// change trains because the dataset does not say the train continues.
  repeatedStop,

  /// `line_service.through_service_of`: same train, no change.
  throughRunning,
}

enum RouteWarningCode {
  /// An interchange without a known walking time was estimated.
  unverifiedTransfer,

  /// A change at a station the same service visits twice.
  repeatedStopChange,

  /// More than one ticket is needed (operator change or leaving the station).
  separateTicket,

  /// No `timing` row for a boarding, so the last train could not be checked.
  lastTrainUnknown,

  /// A boarding is after the last departure of its direction.
  lastTrainRisk,
}

class RouteWarning {
  const RouteWarning(this.code, {this.stationId, this.legIndex});

  final RouteWarningCode code;
  final String? stationId;
  final int? legIndex;

  @override
  String toString() => 'RouteWarning(${code.name}, $stationId, $legIndex)';
}

sealed class Leg {
  const Leg();

  /// Seconds this leg adds to the journey (including waiting).
  int get durationS;
}

/// Time on one train from [fromStationId] to [toStationId].
final class RideLeg extends Leg {
  const RideLeg({
    required this.serviceId,
    required this.lineId,
    required this.operatorId,
    required this.stationIds,
    required this.rideS,
    required this.distanceM,
    required this.waitS,
    required this.rideEstimated,
    required this.provenance,
    this.directionTerminalId,
  });

  final String serviceId;
  final String lineId;
  final String operatorId;

  /// Every stop in travel order, boarding and alighting stations included.
  final List<String> stationIds;

  /// Last stop of the service in the travel direction; null for loops and for
  /// services that visit a station twice (direction is ambiguous).
  final String? directionTerminalId;

  /// On-train seconds.
  final int rideS;
  final int distanceM;

  /// Wait before boarding (only the first boarding and boardings after a
  /// walk; changes put their wait in [TransferLeg.waitS]).
  final int waitS;

  /// true when any hop used the fallback ride time.
  final bool rideEstimated;

  /// Distinct provenance of the edges ridden.
  final List<Provenance> provenance;

  String get fromStationId => stationIds.first;
  String get toStationId => stationIds.last;

  /// Number of hops (stations passed after boarding).
  int get stopCount => stationIds.length - 1;

  @override
  int get durationS => waitS + rideS;
}

/// Change of train inside the paid area.
final class TransferLeg extends Leg {
  const TransferLeg({
    required this.kind,
    required this.stationId,
    required this.fromServiceId,
    required this.toServiceId,
    required this.fromLineId,
    required this.toLineId,
    required this.walkS,
    required this.walkM,
    required this.waitS,
    required this.walkEstimated,
    this.stepFree,
    this.notesEn,
    this.notesHi,
    this.provenance,
  });

  final TransferKind kind;
  final String stationId;
  final String fromServiceId;
  final String toServiceId;
  final String fromLineId;
  final String toLineId;
  final int walkS;
  final int walkM;
  final int waitS;

  /// true when [walkS] or [walkM] is a fallback, not dataset data.
  final bool walkEstimated;

  /// null = unknown.
  final bool? stepFree;
  final String? notesEn;
  final String? notesHi;

  /// Provenance of the `transfer` row; null when no row was used.
  final Provenance? provenance;

  @override
  int get durationS => walkS + waitS;
}

/// Out-of-system walk between two stations (`walk_link`).
final class WalkLeg extends Leg {
  const WalkLeg({
    required this.linkId,
    required this.fromStationId,
    required this.toStationId,
    required this.walkS,
    required this.walkM,
    required this.requiresExit,
    required this.provenance,
    this.stepFree,
  });

  final String linkId;
  final String fromStationId;
  final String toStationId;
  final int walkS;
  final int walkM;
  final bool requiresExit;
  final bool? stepFree;
  final Provenance provenance;

  @override
  int get durationS => walkS;
}

class Itinerary {
  const Itinerary({
    required this.profiles,
    required this.legs,
    required this.totalTimeS,
    required this.changes,
    required this.stops,
    required this.walkM,
    required this.assumptions,
    required this.timeModelId,
    required this.warnings,
    this.fare,
  });

  /// Profiles this route wins (several when identical routes were merged).
  final List<RoutingProfile> profiles;
  final List<Leg> legs;
  final int totalTimeS;

  /// Changes of train plus out-of-system walks (through-running is free).
  final int changes;
  final int stops;
  final int walkM;

  /// `Assumption` codes the times rely on. Never empty today because the
  /// dataset carries no headways: times are approximate by construction.
  final List<String> assumptions;
  final String timeModelId;
  final List<RouteWarning> warnings;
  final FareQuote? fare;

  bool get timeIsEstimate => assumptions.isNotEmpty;

  Iterable<RideLeg> get rides => legs.whereType<RideLeg>();

  /// Identity of the physical route (profiles and fare excluded).
  String get signature => [
    for (final l in legs)
      switch (l) {
        RideLeg() =>
          'R:${l.serviceId}:${l.stationIds.first}>${l.stationIds.last}'
              ':${l.stationIds.length}',
        TransferLeg() =>
          'T:${l.kind.name}:${l.stationId}:${l.fromServiceId}>${l.toServiceId}',
        WalkLeg() => 'W:${l.linkId}:${l.fromStationId}>${l.toStationId}',
      },
  ].join('|');

  Itinerary withFare(FareQuote quote, List<RouteWarning> extraWarnings) =>
      Itinerary(
        profiles: profiles,
        legs: legs,
        totalTimeS: totalTimeS,
        changes: changes,
        stops: stops,
        walkM: walkM,
        assumptions: assumptions,
        timeModelId: timeModelId,
        warnings: [...warnings, ...extraWarnings],
        fare: quote,
      );

  Itinerary withProfiles(List<RoutingProfile> p) => Itinerary(
    profiles: p,
    legs: legs,
    totalTimeS: totalTimeS,
    changes: changes,
    stops: stops,
    walkM: walkM,
    assumptions: assumptions,
    timeModelId: timeModelId,
    warnings: warnings,
    fare: fare,
  );
}

enum RouteStatus {
  ok,
  sameStation,
  unknownStation,

  /// Station exists but no open service stops there.
  notServed,

  /// Both stations are served but no path joins them.
  noRoute,
}

class RouteResult {
  const RouteResult(this.status, {this.itineraries = const [], this.detail});

  final RouteStatus status;

  /// Best first; at most the planner's `maxAlternatives`.
  final List<Itinerary> itineraries;

  /// Machine-readable context (station id, reason). Never user text.
  final String? detail;

  bool get isOk => status == RouteStatus.ok;
  Itinerary? get best => itineraries.isEmpty ? null : itineraries.first;
}
