import 'package:metro_core/metro_core.dart';

/// Human-readable lines for one itinerary (used by the `route` command to
/// eyeball real data; the app renders its own UI from the same objects).
List<String> describeItinerary(MetroSnapshot s, Itinerary it) {
  String station(String id) => s.station(id)?.nameEn ?? id;
  String line(String id) => s.line(id)?.nameEn ?? id;
  final summary =
      '${it.profiles.map((p) => p.name).join(', ')}: '
      '~${(it.totalTimeS / 60).round()} min'
      '${it.timeIsEstimate ? ' (approximate)' : ''}, '
      '${it.changes} change(s), ${it.stops} stop(s), ${it.walkM} m walking';
  final lines = <String>[summary];
  for (final l in it.legs) {
    switch (l) {
      case RideLeg():
        final towards = l.directionTerminalId == null
            ? ''
            : ' towards ${station(l.directionTerminalId!)}';
        lines.add(
          '  ride ${line(l.lineId)}$towards: ${station(l.fromStationId)} -> '
          '${station(l.toStationId)} (${l.stopCount} stops)',
        );
      case TransferLeg():
        lines.add(
          '  ${l.kind == TransferKind.throughRunning ? 'stay on train' : 'change'}'
          ' at ${station(l.stationId)}: ${line(l.fromLineId)} -> '
          '${line(l.toLineId)}'
          '${l.kind == TransferKind.throughRunning ? '' : ' [${l.kind.name}, walk ${l.walkS}s${l.walkEstimated ? ' estimated' : ''}]'}',
        );
      case WalkLeg():
        lines.add(
          '  walk ${station(l.fromStationId)} -> ${station(l.toStationId)} '
          '(${l.walkM} m${l.requiresExit ? ', leaves paid area' : ''})',
        );
    }
  }
  final fare = it.fare;
  if (fare != null) {
    lines.add(
      '  fare: ${fare.isAvailable ? '${fare.totalPaise! / 100} ${fare.currency}'
                '${fare.separateTicket ? ' (separate tickets)' : ''}' : 'unavailable (${fare.status.name}${fare.segments.isEmpty ? '' : ': ${fare.segments.map((x) => x.gap?.name ?? 'priced').join(', ')}'})'}',
    );
  }
  for (final w in it.warnings) {
    lines.add(
      '  warning: ${w.code.name}${w.stationId == null ? '' : ' @ ${w.stationId}'}',
    );
  }
  return lines;
}

Map<String, Object?> itineraryJson(Itinerary it) => {
  'profiles': [for (final p in it.profiles) p.name],
  'total_time_s': it.totalTimeS,
  'changes': it.changes,
  'stops': it.stops,
  'walk_m': it.walkM,
  'assumptions': it.assumptions,
  'time_model': it.timeModelId,
  'legs': [
    for (final l in it.legs)
      switch (l) {
        RideLeg() => {
          'type': 'ride',
          'service': l.serviceId,
          'line': l.lineId,
          'stations': l.stationIds,
          'towards': l.directionTerminalId,
          'wait_s': l.waitS,
          'ride_s': l.rideS,
          'ride_estimated': l.rideEstimated,
          'distance_m': l.distanceM,
          'provenance': [
            for (final p in l.provenance)
              {'source': p.sourceId, 'confidence': p.confidence.wire},
          ],
        },
        TransferLeg() => {
          'type': 'transfer',
          'kind': l.kind.name,
          'station': l.stationId,
          'from_line': l.fromLineId,
          'to_line': l.toLineId,
          'walk_s': l.walkS,
          'walk_m': l.walkM,
          'wait_s': l.waitS,
          'walk_estimated': l.walkEstimated,
          'step_free': l.stepFree,
          'provenance': l.provenance == null
              ? null
              : {
                  'source': l.provenance!.sourceId,
                  'confidence': l.provenance!.confidence.wire,
                  'verified_on': l.provenance!.verifiedOn,
                },
        },
        WalkLeg() => {
          'type': 'walk',
          'link': l.linkId,
          'from': l.fromStationId,
          'to': l.toStationId,
          'walk_s': l.walkS,
          'walk_m': l.walkM,
          'requires_exit': l.requiresExit,
        },
      },
  ],
  'warnings': [
    for (final w in it.warnings)
      {'code': w.code.name, 'station': w.stationId, 'leg': w.legIndex},
  ],
  'fare': it.fare == null
      ? null
      : {
          'status': it.fare!.status.name,
          'total_paise': it.fare!.totalPaise,
          'currency': it.fare!.currency,
          'separate_ticket': it.fare!.separateTicket,
          'confidence': it.fare!.confidence?.wire,
          'segments': [
            for (final x in it.fare!.segments)
              {
                'operator': x.operatorId,
                'from': x.fromStationId,
                'to': x.toStationId,
                'amount_paise': x.amountPaise,
                'basis': x.basis?.name,
                'gap': x.gap?.name,
                'source': x.sourceId,
              },
          ],
        },
};

/// The `routing` section of build-report.json: how connected the network is
/// and how much of the routing input is unknown (so the numbers a router will
/// print are mostly estimates).
Map<String, Object?> routingReport(MetroSnapshot s, TravelTimeModel model) {
  final planner = RoutePlanner(s, model: model);
  final components = planner.stationComponents();
  return {
    'components': components.length,
    'component_sizes': [for (final c in components) c.length],
    'smaller_components': [
      for (final c in components.skip(1))
        {'size': c.length, 'stations': c.take(12).toList()},
    ],
    'stations_not_served':
        s.stations.length - components.fold<int>(0, (a, c) => a + c.length),
    'interchange_rows': s.transfers.length,
    'interchange_rows_without_walk_time': s.transfers
        .where((t) => t.walkS == null)
        .length,
    'edges': s.edges.length,
    'edges_without_travel_time': s.edges.where((e) => e.travelS == null).length,
    'fare_systems': s.fareSystems.length,
    'timings': s.timings.length,
    'time_model': model.toJson(),
    'time_model_status':
        'unapproved-placeholder: replace with owner-approved '
        'values or real travel_s data before release (ADR-035)',
  };
}
