import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/routing/itinerary.dart';

/// Checks every boarding of [itinerary] against the dataset's last departures.
///
/// [departMinute] is minutes since 00:00 of the service day (may exceed 1440
/// for post-midnight). Times follow the itinerary's own (approximate) leg
/// durations. A boarding with no `timing` row for (service, station, direction,
/// day type) yields [RouteWarningCode.lastTrainUnknown] - absence of data is
/// never read as "a train will run".
List<RouteWarning> checkLastTrain(
  MetroSnapshot snapshot,
  Itinerary itinerary, {
  required int departMinute,
  DayType dayType = DayType.regular,
}) {
  final warnings = <RouteWarning>[];
  var cursorS = departMinute * 60;
  for (var i = 0; i < itinerary.legs.length; i++) {
    final leg = itinerary.legs[i];
    if (leg is RideLeg) {
      final boardS = cursorS + leg.waitS;
      final terminal = leg.directionTerminalId;
      final timing = terminal == null
          ? null
          : snapshot.timings
                .where(
                  (t) =>
                      t.serviceId == leg.serviceId &&
                      t.stationId == leg.fromStationId &&
                      t.directionTerminalId == terminal &&
                      t.dayType == dayType,
                )
                .firstOrNull;
      if (timing == null) {
        warnings.add(
          RouteWarning(
            RouteWarningCode.lastTrainUnknown,
            stationId: leg.fromStationId,
            legIndex: i,
          ),
        );
      } else if (boardS > timing.lastDep * 60) {
        warnings.add(
          RouteWarning(
            RouteWarningCode.lastTrainRisk,
            stationId: leg.fromStationId,
            legIndex: i,
          ),
        );
      }
    }
    cursorS += leg.durationS;
  }
  return warnings;
}
