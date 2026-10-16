import 'dart:math' as math;

import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/network.dart';

/// Whether [lat]/[lng] is a usable WGS84 coordinate: finite and in range.
/// (0, 0) is a valid point in the ocean, but it is also the classic "no fix"
/// value, so it is treated as invalid too.
bool isValidCoordinate(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
  return !(lat == 0 && lng == 0);
}

/// Default search radius and result count of [findNearbyStations].
const defaultNearbyRadiusM = 5000.0;
const defaultNearbyLimit = 10;

const _earthRadiusM = 6371008.8;

/// Great-circle (straight-line over the surface) distance in metres.
/// Haversine on a spherical Earth: accurate to ~0.5 %, which is plenty for
/// "how far is the nearest station". It is **not** a walking distance.
double straightLineDistanceM(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
}

class NearbyStation {
  const NearbyStation({required this.station, required this.distanceM});

  final Station station;

  /// Straight-line distance from the query point, in metres (whole metres).
  final int distanceM;
}

/// Stations within [maxDistanceM] of a point, nearest first.
///
/// Deterministic: sorted by the rounded distance in metres, then by station
/// id. Stations whose own coordinates are invalid are skipped (never placed at
/// a made-up location), as are stations that are not open when [onlyOpen].
/// An invalid query point yields an empty list; callers should check
/// [isValidCoordinate] first to tell "bad location" from "nothing nearby".
List<NearbyStation> findNearbyStations(
  Iterable<Station> stations, {
  required double lat,
  required double lng,
  double maxDistanceM = defaultNearbyRadiusM,
  int limit = defaultNearbyLimit,
  bool onlyOpen = true,
}) {
  if (!isValidCoordinate(lat, lng) || limit <= 0) return const [];
  final out = <NearbyStation>[];
  for (final s in stations) {
    if (onlyOpen && s.status != OperatingStatus.open) continue;
    if (!isValidCoordinate(s.lat, s.lng)) continue;
    final d = straightLineDistanceM(lat, lng, s.lat, s.lng).round();
    if (d <= maxDistanceM) out.add(NearbyStation(station: s, distanceM: d));
  }
  out.sort((a, b) {
    final c = a.distanceM.compareTo(b.distanceM);
    return c != 0 ? c : a.station.id.compareTo(b.station.id);
  });
  return List.unmodifiable(out.take(limit));
}
