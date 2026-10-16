import 'package:metro_core/metro_core.dart' hide Platform;

/// What a route adds to the map. Built only from the legs of an itinerary
/// and the drawable geometry: nothing is drawn that the route does not
/// contain, and no walking geometry is invented.
class MapOverlay {
  const MapOverlay({
    required this.highlightedSegments,
    required this.routeStationIds,
    required this.transferStationIds,
    required this.walks,
    required this.lineIds,
    required this.fromId,
    required this.toId,
  });

  /// [MapSegment.key]s of the segments the route rides.
  final Set<String> highlightedSegments;

  /// Drawable stations of the route in travel order, without repeats.
  final List<String> routeStationIds;

  /// Drawable stations where the rider changes trains (not through-running).
  final List<String> transferStationIds;

  /// Out-of-system walks that are legs of the route and have both ends
  /// drawable: `(fromId, toId)`. Drawn as a plain dashed link between the two
  /// stations; its length or duration is never shown on the map.
  final List<(String, String)> walks;

  /// Lines ridden, in order of first use.
  final List<String> lineIds;
  final String fromId;
  final String toId;

  /// Whether there is anything to draw for the route.
  bool get hasGeometry => routeStationIds.isNotEmpty;
}

/// The overlay of [itinerary] on [geometry].
MapOverlay overlayFor(MapGeometry geometry, Itinerary itinerary) {
  final segments = <String>{};
  final stations = <String>[];
  final transfers = <String>[];
  final walks = <(String, String)>[];
  final lines = <String>[];

  void addStation(String id) {
    if (geometry.station(id) != null && !stations.contains(id)) {
      stations.add(id);
    }
  }

  for (final leg in itinerary.legs) {
    switch (leg) {
      case RideLeg():
        if (!lines.contains(leg.lineId)) lines.add(leg.lineId);
        for (var i = 0; i < leg.stationIds.length; i++) {
          addStation(leg.stationIds[i]);
          if (i + 1 < leg.stationIds.length) {
            final a = leg.stationIds[i];
            final b = leg.stationIds[i + 1];
            final seg = a.compareTo(b) < 0
                ? MapSegment(lineId: leg.lineId, fromId: a, toId: b)
                : MapSegment(lineId: leg.lineId, fromId: b, toId: a);
            segments.add(seg.key);
          }
        }
      case TransferLeg():
        if (leg.kind != TransferKind.throughRunning &&
            geometry.station(leg.stationId) != null &&
            !transfers.contains(leg.stationId)) {
          transfers.add(leg.stationId);
        }
      case WalkLeg():
        addStation(leg.fromStationId);
        addStation(leg.toStationId);
        if (geometry.station(leg.fromStationId) != null &&
            geometry.station(leg.toStationId) != null) {
          walks.add((leg.fromStationId, leg.toStationId));
        }
    }
  }
  final known = {for (final s in geometry.segments) s.key};
  final first = itinerary.legs.isEmpty ? null : itinerary.legs.first;
  final last = itinerary.legs.isEmpty ? null : itinerary.legs.last;
  return MapOverlay(
    highlightedSegments: Set.unmodifiable(segments.intersection(known)),
    routeStationIds: List.unmodifiable(stations),
    transferStationIds: List.unmodifiable(transfers),
    walks: List.unmodifiable(walks),
    lineIds: List.unmodifiable(lines),
    fromId: switch (first) {
      RideLeg(:final fromStationId) => fromStationId,
      WalkLeg(:final fromStationId) => fromStationId,
      TransferLeg(:final stationId) => stationId,
      null => '',
    },
    toId: switch (last) {
      RideLeg(:final toStationId) => toStationId,
      WalkLeg(:final toStationId) => toStationId,
      TransferLeg(:final stationId) => stationId,
      null => '',
    },
  );
}
