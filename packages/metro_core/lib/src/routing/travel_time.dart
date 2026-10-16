/// Codes naming every assumption an itinerary's times rely on. They are listed
/// in `Itinerary.assumptions` so the UI can label times as approximate and the
/// numbers can be audited (docs/routing.md "Travel-time fallback").
abstract final class Assumption {
  /// Ride time of an edge with no `travel_s`: dwell + distance / speed.
  static const rideTimeEstimated = 'ride_time_estimated';

  /// No headway data exists, so every boarding costs a fixed wait.
  static const boardingWait = 'boarding_wait';

  /// Interchange row with unknown `walk_s`.
  static const transferWalkTimeEstimated = 'transfer_walk_time_estimated';

  /// Interchange row with unknown `walk_m` (only used to rank "less walking").
  static const transferWalkDistanceEstimated =
      'transfer_walk_distance_estimated';
}

/// The documented travel-time fallback (ADR-035).
///
/// Dataset values always win: `edge.travel_s`, `transfer.walk_s`/`walk_m` are
/// used when present. Only when a value is unknown (NULL) is the parameter
/// below substituted, and the substitution is reported via [Assumption] codes.
///
/// The defaults are **generic placeholders, not measurements of any network**.
/// They exist so routing can rank alternatives offline; they must be replaced
/// by owner-approved values (or by real `travel_s` data) before a release, and
/// the UI must present resulting times as approximate.
class TravelTimeModel {
  const TravelTimeModel({
    this.id = 'fallback-v1',
    this.cruiseSpeedKmh = 35,
    this.dwellS = 25,
    this.boardWaitS = 180,
    this.transferWalkS = 240,
    this.transferWalkM = 200,
  }) : assert(cruiseSpeedKmh > 0, 'speed must be positive');

  /// Recorded with every itinerary so a number can be traced to its rules.
  final String id;

  /// Average speed between stops (km/h). Edge distances are straight-line
  /// (haversine), so real rides are longer than this model assumes.
  final double cruiseSpeedKmh;

  /// Time at a station per hop (seconds).
  final int dwellS;

  /// Wait before boarding a train, used for the first boarding and after every
  /// change (seconds).
  final int boardWaitS;

  /// Interchange walk when the dataset has no `walk_s` (seconds).
  final int transferWalkS;

  /// Interchange walk distance when the dataset has no `walk_m` (metres).
  final int transferWalkM;

  /// Estimated ride seconds for a hop of [distanceM] metres.
  int estimateRideS(int distanceM) =>
      dwellS + (distanceM * 3.6 / cruiseSpeedKmh).round();

  Map<String, Object> toJson() => {
    'id': id,
    'cruise_speed_kmh': cruiseSpeedKmh,
    'dwell_s': dwellS,
    'board_wait_s': boardWaitS,
    'transfer_walk_s': transferWalkS,
    'transfer_walk_m': transferWalkM,
  };
}
