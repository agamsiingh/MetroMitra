import 'dart:math' as math;

import 'package:metro_core/src/geo/nearby.dart';
import 'package:metro_core/src/model/snapshot.dart';

/// Axis-aligned rectangle in the map plane.
class MapRect {
  const MapRect(this.minX, this.minY, this.maxX, this.maxY);

  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;

  @override
  String toString() => 'MapRect($minX, $minY, $maxX, $maxY)';
}

/// A station that can be drawn: it has a usable coordinate. [id] is the
/// canonical station id; names never identify a map marker.
class MapStation {
  const MapStation({
    required this.id,
    required this.x,
    required this.y,
    required this.lineIds,
  });

  final String id;

  /// Position in the map plane (see [MapGeometry]).
  final double x;
  final double y;

  /// Lines serving the station, sorted.
  final List<String> lineIds;

  bool get isInterchange => lineIds.length >= 2;
}

/// A connection between two consecutive stops of a service, drawn in the
/// colour of its line. It is a straight stop-to-stop link, **not** surveyed
/// track geometry (the dataset holds no track shapes), and is never curved
/// or invented.
class MapSegment {
  const MapSegment({
    required this.lineId,
    required this.fromId,
    required this.toId,
  });

  final String lineId;

  /// `fromId` sorts before `toId`: a segment has no direction.
  final String fromId;
  final String toId;

  String get key => '$lineId|$fromId|$toId';
}

class _Stop {
  const _Stop(this.seq, this.stationId);

  final int seq;
  final String stationId;
}

/// Everything needed to draw the network, derived from a snapshot with no
/// UI, network or platform dependency.
///
/// - Plane: equirectangular around the centre of the drawable stations'
///   bounding box; x grows east, y grows **south** (screen orientation).
///   Units are degrees of latitude (about 111 km).
/// - Deterministic: stations are ordered by id, segments by line, then ids;
///   the result does not depend on input order.
/// - Honest: stations without a valid coordinate and segments with an
///   undrawable end are left out and counted, never placed at a guess.
class MapGeometry {
  MapGeometry._({
    required this.stations,
    required this.segments,
    required this.skippedStationIds,
    required this.skippedSegmentCount,
    this.origin,
  }) : _byId = {for (final s in stations) s.id: s} {
    for (final s in stations) {
      (_grid[_cellKey((s.x / _cell).floor(), (s.y / _cell).floor())] ??= [])
          .add(s);
    }
  }

  factory MapGeometry.fromSnapshot(MetroSnapshot snap) {
    final valid = [
      for (final s in snap.stations)
        if (isValidCoordinate(s.lat, s.lng)) s,
    ]..sort((a, b) => a.id.compareTo(b.id));
    final skipped = [
      for (final s in snap.stations)
        if (!isValidCoordinate(s.lat, s.lng)) s.id,
    ]..sort();
    if (valid.isEmpty) {
      return MapGeometry._(
        stations: const [],
        segments: const [],
        skippedStationIds: List.unmodifiable(skipped),
        skippedSegmentCount: 0,
      );
    }
    var minLat = valid.first.lat;
    var maxLat = minLat;
    var minLng = valid.first.lng;
    var maxLng = minLng;
    for (final s in valid) {
      minLat = math.min(minLat, s.lat);
      maxLat = math.max(maxLat, s.lat);
      minLng = math.min(minLng, s.lng);
      maxLng = math.max(maxLng, s.lng);
    }
    final lat0 = (minLat + maxLat) / 2;
    final lng0 = (minLng + maxLng) / 2;
    final k = math.cos(lat0 * math.pi / 180);

    final lineIdsAt = <String, Set<String>>{};
    for (final sl in snap.stationLines) {
      (lineIdsAt[sl.stationId] ??= {}).add(sl.lineId);
    }
    final stations = [
      for (final s in valid)
        MapStation(
          id: s.id,
          x: _q((s.lng - lng0) * k),
          y: _q(-(s.lat - lat0)),
          lineIds: List.unmodifiable((lineIdsAt[s.id] ?? {}).toList()..sort()),
        ),
    ];
    final drawable = {for (final s in stations) s.id};

    final lineOfService = {for (final s in snap.services) s.id: s.lineId};
    final stopsByService = <String, List<_Stop>>{};
    for (final st in snap.serviceStops) {
      (stopsByService[st.serviceId] ??= []).add(_Stop(st.seq, st.stationId));
    }
    final segs = <String, MapSegment>{};
    var skippedSegments = 0;
    for (final e in stopsByService.entries) {
      final lineId = lineOfService[e.key];
      if (lineId == null) continue;
      final stops = e.value..sort((a, b) => a.seq.compareTo(b.seq));
      for (var i = 0; i + 1 < stops.length; i++) {
        final a = stops[i].stationId;
        final b = stops[i + 1].stationId;
        if (a == b) continue;
        if (!drawable.contains(a) || !drawable.contains(b)) {
          skippedSegments++;
          continue;
        }
        final seg = a.compareTo(b) < 0
            ? MapSegment(lineId: lineId, fromId: a, toId: b)
            : MapSegment(lineId: lineId, fromId: b, toId: a);
        segs[seg.key] = seg;
      }
    }
    final segments = segs.values.toList()
      ..sort((a, b) {
        final c = a.lineId.compareTo(b.lineId);
        if (c != 0) return c;
        final d = a.fromId.compareTo(b.fromId);
        return d != 0 ? d : a.toId.compareTo(b.toId);
      });
    return MapGeometry._(
      stations: List.unmodifiable(stations),
      segments: List.unmodifiable(segments),
      skippedStationIds: List.unmodifiable(skipped),
      skippedSegmentCount: skippedSegments,
      origin: (lat0, lng0, k),
    );
  }

  /// Drawable stations, ordered by id.
  final List<MapStation> stations;

  /// Drawable connections, ordered by line then ids; one per line and pair.
  final List<MapSegment> segments;

  /// Stations left out for lack of a usable coordinate.
  final List<String> skippedStationIds;

  /// Stop-to-stop links left out because an end is not drawable.
  final int skippedSegmentCount;

  final Map<String, MapStation> _byId;

  /// Projection centre and longitude scale; null for an empty network.
  final (double, double, double)? origin;

  /// A geographic point in the same plane as the stations (e.g. the user's
  /// position), or null when the point or the network is unusable.
  (double, double)? project(double lat, double lng) {
    final o = origin;
    if (o == null || !isValidCoordinate(lat, lng)) return null;
    final (lat0, lng0, k) = o;
    return ((lng - lng0) * k, -(lat - lat0));
  }

  /// Frame around [ids] plus extra plane points (e.g. the user's position).
  MapRect? framingWith(
    Iterable<String> ids,
    Iterable<(double, double)> points, {
    double span = stationSpan,
  }) {
    final xs = <double>[
      for (final id in ids)
        if (_byId[id] != null) _byId[id]!.x,
      for (final p in points) p.$1,
    ];
    final ys = <double>[
      for (final id in ids)
        if (_byId[id] != null) _byId[id]!.y,
      for (final p in points) p.$2,
    ];
    if (xs.isEmpty) return null;
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final cx = _q((minX + maxX) / 2);
    final cy = _q((minY + maxY) / 2);
    final w = _q(math.max((maxX - minX) * 1.4, span));
    final h = _q(math.max((maxY - minY) * 1.4, span));
    return MapRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2);
  }

  bool get isEmpty => stations.isEmpty;

  MapStation? station(String id) => _byId[id];

  /// Smallest extent a frame may have, so one station (or several at the
  /// same spot) still gets a sensible view: about 440 m.
  static const minSpan = 0.004;

  /// Span used when framing a single station: about 2.2 km, enough to see
  /// its neighbours.
  static const stationSpan = 0.02;

  /// Frame of every drawable station; null for an empty network.
  MapRect? get networkFrame => framingFor(_byId.keys);

  /// Frame around [ids] (unknown / undrawable ids are ignored); null when
  /// none is drawable. Degenerate extents grow to [span]. Quantised so the
  /// result never depends on floating-point summation order.
  MapRect? framingFor(Iterable<String> ids, {double span = minSpan}) {
    double? minX;
    double? minY;
    double? maxX;
    double? maxY;
    for (final id in ids) {
      final s = _byId[id];
      if (s == null) continue;
      minX = minX == null ? s.x : math.min(minX, s.x);
      maxX = maxX == null ? s.x : math.max(maxX, s.x);
      minY = minY == null ? s.y : math.min(minY, s.y);
      maxY = maxY == null ? s.y : math.max(maxY, s.y);
    }
    if (minX == null || minY == null || maxX == null || maxY == null) {
      return null;
    }
    final cx = _q((minX + maxX) / 2);
    final cy = _q((minY + maxY) / 2);
    final w = _q(math.max(maxX - minX, span));
    final h = _q(math.max(maxY - minY, span));
    return MapRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2);
  }

  /// Frame for one station (its neighbourhood).
  MapRect? framingForStation(String id) => framingFor([id], span: stationSpan);

  // ------------------------------------------------------------------ hit test
  static const _cell = 0.005;
  final Map<int, List<MapStation>> _grid = {};

  static int _cellKey(int cx, int cy) => (cx + 100000) * 200003 + (cy + 100000);

  /// The station nearest to a point (plane units) within [maxDistance], or
  /// null. Ties go to the smaller station id. Looks only at nearby grid
  /// cells, so a tap costs O(stations nearby), not O(network).
  MapStation? nearestStation(double x, double y, double maxDistance) {
    if (!x.isFinite || !y.isFinite || !(maxDistance > 0)) return null;
    final r = (maxDistance / _cell).ceil();
    final cx = (x / _cell).floor();
    final cy = (y / _cell).floor();
    MapStation? best;
    var bestD = double.infinity;
    for (var i = cx - r; i <= cx + r; i++) {
      for (var j = cy - r; j <= cy + r; j++) {
        for (final s in _grid[_cellKey(i, j)] ?? const <MapStation>[]) {
          final dx = s.x - x;
          final dy = s.y - y;
          final d = math.sqrt(dx * dx + dy * dy);
          if (d > maxDistance) continue;
          if (d < bestD || (d == bestD && s.id.compareTo(best!.id) < 0)) {
            best = s;
            bestD = d;
          }
        }
      }
    }
    return best;
  }

  /// Round to 1e-7 units (about a centimetre).
  static double _q(double v) => (v * 1e7).roundToDouble() / 1e7;
}
