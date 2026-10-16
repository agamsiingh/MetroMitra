import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/go/application/route_lookup.dart';
import 'package:metromitra/shared/data/journey_store.dart';
import 'package:metromitra/shared/location/location_source.dart';

/// A journey older than this is not offered for resuming (UI choice).
const journeyMaxAge = Duration(hours: 6);

/// GPS snap radius (docs/routing.md "Journey progress model": 250 m).
const journeySnapRadiusM = 250.0;

/// The running journey: the chosen route, its steps and where the rider is.
class ActiveJourney {
  const ActiveJourney({
    required this.fromId,
    required this.toId,
    required this.optionIndex,
    required this.itinerary,
    required this.plan,
    required this.state,
    required this.keepAwake,
  });

  final String fromId;
  final String toId;
  final int optionIndex;
  final Itinerary itinerary;
  final JourneyPlan plan;
  final JourneyState state;

  /// Keep the screen on while the journey screen is open (default on).
  final bool keepAwake;

  JourneyEngine get engine => JourneyEngine(plan);

  ActiveJourney copyWith({JourneyState? state, bool? keepAwake}) =>
      ActiveJourney(
        fromId: fromId,
        toId: toId,
        optionIndex: optionIndex,
        itinerary: itinerary,
        plan: plan,
        state: state ?? this.state,
        keepAwake: keepAwake ?? this.keepAwake,
      );
}

sealed class JourneySession {
  const JourneySession();
}

class NoJourney extends JourneySession {
  const NoJourney();
}

class JourneyRunning extends JourneySession {
  const JourneyRunning(this.journey);

  final ActiveJourney journey;
}

enum RestoreProblem {
  /// The saved journey no longer matches the installed data.
  dataChanged,

  /// Too old to continue.
  expired,
}

/// A saved journey existed but could not be resumed; it has been cleared.
class JourneyNotRestored extends JourneySession {
  const JourneyNotRestored(this.problem);

  final RestoreProblem problem;
}

enum SnapResult { moved, notNear, denied, unavailable, invalid }

/// Runs the journey (step engine from metro_core) and saves every change so
/// it can be resumed after the app is killed. Holds no location: a GPS fix
/// is only used once to pick a station of the route and then dropped.
class JourneyController extends Notifier<JourneySession> {
  @override
  JourneySession build() => const NoJourney();

  int _now() => ref.read(clockProvider)().millisecondsSinceEpoch;

  /// Starts option [optionIndex] of the route [fromId] -> [toId]. Returns
  /// false when that route does not exist (nothing changes).
  Future<bool> start(String fromId, String toId, int optionIndex) async {
    final it = _itinerary(fromId, toId, optionIndex);
    if (it == null) return false;
    final journey = ActiveJourney(
      fromId: fromId,
      toId: toId,
      optionIndex: optionIndex,
      itinerary: it,
      plan: JourneyPlan.fromItinerary(
        ref.read(metroServicesProvider).snapshot,
        it,
      ),
      state: JourneyState.start(_now()),
      keepAwake: true,
    );
    await _set(journey);
    return true;
  }

  Future<void> advance() async {
    final j = _running;
    if (j == null) return;
    final next = j.engine.advance(j.state, _now());
    if (next == null) {
      await end();
    } else {
      await _set(j.copyWith(state: next));
    }
  }

  /// "I'm at [stationId]". False when the station is not on the route.
  Future<bool> correctTo(String stationId) async {
    final j = _running;
    if (j == null) return false;
    final next = j.engine.correctTo(j.state, stationId, _now());
    if (next == null) return false;
    await _set(j.copyWith(state: next));
    return true;
  }

  /// One location fix, snapped to the nearest station of the route within
  /// [journeySnapRadiusM]. The fix is not kept.
  Future<(SnapResult, String?)> snapToLocation() async {
    final j = _running;
    if (j == null) return (SnapResult.unavailable, null);
    final fix = await ref.read(locationSourceProvider).current();
    if (!ref.mounted) return (SnapResult.unavailable, null);
    switch (fix) {
      case LocationDenied():
        return (SnapResult.denied, null);
      case LocationUnavailable():
        return (SnapResult.unavailable, null);
      case LocationFix(:final lat, :final lng):
        if (!isValidCoordinate(lat, lng)) return (SnapResult.invalid, null);
        final route = j.engine.correctableStations().toSet();
        final snapshot = ref.read(metroServicesProvider).snapshot;
        final near = findNearbyStations(
          [
            for (final id in route) ?snapshot.station(id),
          ],
          lat: lat,
          lng: lng,
          maxDistanceM: journeySnapRadiusM,
          limit: 1,
        );
        if (near.isEmpty) return (SnapResult.notNear, null);
        final id = near.first.station.id;
        await correctTo(id);
        return (SnapResult.moved, id);
    }
  }

  Future<void> setKeepAwake({required bool on}) async {
    final j = _running;
    if (j == null) return;
    await _set(j.copyWith(keepAwake: on));
  }

  Future<void> end() async {
    state = const NoJourney();
    await _clearSaved();
  }

  Future<void> _clearSaved() async {
    try {
      await ref.read(journeyStoreProvider).clear();
    } on Object {
      // a stale row is discarded on the next restore anyway
    }
  }

  /// Forget a "could not restore" notice.
  void dismissNotice() {
    if (state is JourneyNotRestored) state = const NoJourney();
  }

  /// Resumes a saved journey (after the app was killed). Anything that does
  /// not match the installed data exactly is discarded, never patched up.
  Future<void> restore() async {
    if (state is JourneyRunning) return;
    final store = ref.read(journeyStoreProvider);
    final raw = await store.load();
    if (raw == null) return;
    final problem = _restoreFrom(raw);
    if (problem != null) {
      await _clearSaved();
      if (ref.mounted) state = JourneyNotRestored(problem);
    }
  }

  RestoreProblem? _restoreFrom(String raw) {
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return RestoreProblem.dataChanged;
    }
    if (json is! Map || json['v'] != 1) return RestoreProblem.dataChanged;
    final services = ref.read(metroServicesProvider);
    final from = json['from'];
    final to = json['to'];
    final opt = json['opt'];
    final saved = JourneyState.fromJson(json['state']);
    if (from is! String || to is! String || opt is! int || saved == null) {
      return RestoreProblem.dataChanged;
    }
    if (json['dataset'] != services.datasetVersion) {
      return RestoreProblem.dataChanged;
    }
    final age = _now() - saved.startedAtMs;
    if (age < 0 || age > journeyMaxAge.inMilliseconds) {
      return RestoreProblem.expired;
    }
    final it = _itinerary(from, to, opt);
    if (it == null || it.signature != json['signature']) {
      return RestoreProblem.dataChanged;
    }
    final plan = JourneyPlan.fromItinerary(services.snapshot, it);
    state = JourneyRunning(
      ActiveJourney(
        fromId: from,
        toId: to,
        optionIndex: opt,
        itinerary: it,
        plan: plan,
        state: JourneyEngine(plan).normalise(saved),
        keepAwake: json['keepAwake'] != false,
      ),
    );
    return null;
  }

  ActiveJourney? get _running => switch (state) {
    JourneyRunning(:final journey) => journey,
    _ => null,
  };

  Itinerary? _itinerary(String fromId, String toId, int optionIndex) {
    final lookup = ref.read(routeLookupProvider(RouteQuery(fromId, toId)));
    if (lookup is! RouteFound) return null;
    if (optionIndex < 0 || optionIndex >= lookup.options.length) return null;
    return lookup.options[optionIndex].itinerary;
  }

  Future<void> _set(ActiveJourney j) async {
    state = JourneyRunning(j);
    final json = jsonEncode({
      'v': 1,
      'dataset': ref.read(metroServicesProvider).datasetVersion,
      'from': j.fromId,
      'to': j.toId,
      'opt': j.optionIndex,
      'signature': j.plan.signature,
      'state': j.state.toJson(),
      'keepAwake': j.keepAwake,
    });
    try {
      await ref.read(journeyStoreProvider).save(json, _now());
    } on Object {
      // saving is best effort: the journey goes on in memory
    }
  }
}

final activeJourneyProvider =
    NotifierProvider<JourneyController, JourneySession>(JourneyController.new);

/// Runs [JourneyController.restore] once after the dataset is ready.
final journeyRestoreProvider = FutureProvider<void>((ref) async {
  await ref.read(activeJourneyProvider.notifier).restore();
});
