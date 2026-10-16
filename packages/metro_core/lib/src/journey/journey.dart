import 'package:metro_core/src/model/provenance.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/routing/itinerary.dart';

/// What the rider does in one step of a journey (docs/requirements.md
/// FR-JOURNEY 1): enter -> board -> ride -> change / walk -> ... -> exit.
enum JourneyStepKind {
  /// Go into the origin station.
  enter,

  /// Wait for and board a train: line, direction and (only if the data has
  /// it) platform.
  board,

  /// On the train; stops remaining are estimated from the route times.
  ride,

  /// Change trains inside the paid area.
  change,

  /// Stay on the train: the service continues as another line.
  stayOnBoard,

  /// Out-of-system walk between two stations.
  walk,

  /// Leave the destination station.
  exit,
}

/// A platform row the dataset has for a boarding; never guessed.
class PlatformInfo {
  const PlatformInfo({required this.number, required this.provenance});

  final String number;
  final Provenance provenance;
}

/// A gate the dataset lists at a station, with its landmarks. Gates the data
/// marks as closed are left out; unknown (null) open state is kept.
class GateInfo {
  const GateInfo({
    required this.id,
    required this.number,
    required this.provenance,
    this.nameEn,
    this.nameHi,
    this.landmarksEn = const [],
    this.landmarksHi = const [],
    this.hasLift,
    this.isStepFree,
  });

  final String id;
  final int number;
  final String? nameEn;
  final String? nameHi;

  /// Landmark texts in English; [landmarksHi] holds the Hindi text of the
  /// same landmark, or null when the data has none.
  final List<String> landmarksEn;
  final List<String?> landmarksHi;
  final bool? hasLift;
  final bool? isStepFree;
  final Provenance provenance;
}

class JourneyStep {
  const JourneyStep({
    required this.kind,
    required this.stationId,
    required this.legIndex,
    this.lineId,
    this.toLineId,
    this.towardsStationId,
    this.platform,
    this.stationIds = const [],
    this.toStationId,
    this.walkM,
    this.walkS,
    this.walkEstimated = false,
    this.requiresExit = false,
    this.stepFree,
    this.gates = const [],
    this.rideS = 0,
    this.transferKind,
  });

  final JourneyStepKind kind;

  /// Where the step happens (boarding station for board/ride, change station,
  /// walk start, destination for exit).
  final String stationId;

  /// Index of the itinerary leg this step comes from (-1 for enter / exit).
  final int legIndex;

  /// Line ridden (board/ride/stayOnBoard) or left (change).
  final String? lineId;

  /// Line changed to (change / stayOnBoard).
  final String? toLineId;

  /// "Towards" terminal; null when the data cannot name one (loops, seams).
  final String? towardsStationId;

  /// Platform from the dataset; null = unknown (never guessed).
  final PlatformInfo? platform;

  /// Ride: every stop in travel order (boarding and alighting included).
  final List<String> stationIds;

  /// Ride: where to get off; walk: where the walk ends.
  final String? toStationId;
  final int? walkM;
  final int? walkS;

  /// The walk time/length of a change is a fallback, not dataset data.
  final bool walkEstimated;

  /// Walk: the rider leaves the paid area (new ticket).
  final bool requiresExit;

  /// null = unknown.
  final bool? stepFree;

  /// Enter / exit: the gates the data lists (may be empty = unknown).
  final List<GateInfo> gates;

  /// Ride: on-train seconds from the route.
  final int rideS;

  /// Change: the kind of change (repeated stop / same line / line change).
  final TransferKind? transferKind;

  /// Ride: hops between boarding and alighting.
  int get stopCount => stationIds.isEmpty ? 0 : stationIds.length - 1;
}

/// The steps of an itinerary, built only from its legs and the dataset.
class JourneyPlan {
  JourneyPlan._(this.steps, this.signature, this.fromId, this.toId);

  /// Builds the steps for [it]. Platforms and gates come from
  /// [snapshot] only; when the data has none they stay unknown.
  factory JourneyPlan.fromItinerary(MetroSnapshot snapshot, Itinerary it) {
    if (it.legs.isEmpty) {
      throw ArgumentError('an itinerary with no legs has no journey');
    }
    final steps = <JourneyStep>[];
    final from = _startOf(it.legs.first);
    final to = _endOf(it.legs.last);
    steps.add(
      JourneyStep(
        kind: JourneyStepKind.enter,
        stationId: from,
        legIndex: -1,
        gates: gatesAt(snapshot, from),
      ),
    );
    var skipBoard = false;
    for (var i = 0; i < it.legs.length; i++) {
      final leg = it.legs[i];
      switch (leg) {
        case RideLeg():
          if (!skipBoard) {
            steps.add(
              JourneyStep(
                kind: JourneyStepKind.board,
                stationId: leg.fromStationId,
                legIndex: i,
                lineId: leg.lineId,
                towardsStationId: leg.directionTerminalId,
                platform: platformFor(snapshot, leg),
              ),
            );
          }
          skipBoard = false;
          steps.add(
            JourneyStep(
              kind: JourneyStepKind.ride,
              stationId: leg.fromStationId,
              legIndex: i,
              lineId: leg.lineId,
              towardsStationId: leg.directionTerminalId,
              stationIds: List.unmodifiable(leg.stationIds),
              toStationId: leg.toStationId,
              rideS: leg.rideS,
            ),
          );
        case TransferLeg():
          if (leg.kind == TransferKind.throughRunning) {
            steps.add(
              JourneyStep(
                kind: JourneyStepKind.stayOnBoard,
                stationId: leg.stationId,
                legIndex: i,
                lineId: leg.fromLineId,
                toLineId: leg.toLineId,
              ),
            );
            skipBoard = true;
          } else {
            steps.add(
              JourneyStep(
                kind: JourneyStepKind.change,
                stationId: leg.stationId,
                legIndex: i,
                lineId: leg.fromLineId,
                toLineId: leg.toLineId,
                walkM: leg.walkM,
                walkS: leg.walkS,
                walkEstimated: leg.walkEstimated,
                stepFree: leg.stepFree,
                transferKind: leg.kind,
              ),
            );
          }
        case WalkLeg():
          steps.add(
            JourneyStep(
              kind: JourneyStepKind.walk,
              stationId: leg.fromStationId,
              legIndex: i,
              toStationId: leg.toStationId,
              walkM: leg.walkM,
              walkS: leg.walkS,
              requiresExit: leg.requiresExit,
              stepFree: leg.stepFree,
              gates: leg.requiresExit
                  ? gatesAt(snapshot, leg.toStationId)
                  : const [],
            ),
          );
      }
    }
    steps.add(
      JourneyStep(
        kind: JourneyStepKind.exit,
        stationId: to,
        legIndex: -1,
        gates: gatesAt(snapshot, to),
      ),
    );
    return JourneyPlan._(List.unmodifiable(steps), it.signature, from, to);
  }

  final List<JourneyStep> steps;

  /// `Itinerary.signature` of the route the plan was built from; used to
  /// check that a saved journey still matches the data after a restart.
  final String signature;
  final String fromId;
  final String toId;

  int get lastIndex => steps.length - 1;

  static String _startOf(Leg l) => switch (l) {
    RideLeg() => l.fromStationId,
    TransferLeg() => l.stationId,
    WalkLeg() => l.fromStationId,
  };

  static String _endOf(Leg l) => switch (l) {
    RideLeg() => l.toStationId,
    TransferLeg() => l.stationId,
    WalkLeg() => l.toStationId,
  };

  /// The platform the dataset gives for boarding [leg], or null. A row must
  /// match the station and line, must not contradict the boarding (a
  /// different service or a different direction), and must name at least one
  /// of them; a row with neither is not specific enough. Two different
  /// platform numbers for the same boarding = ambiguous = null.
  static PlatformInfo? platformFor(MetroSnapshot snapshot, RideLeg leg) {
    final rows = [
      for (final p in snapshot.platformsAt(leg.fromStationId))
        if (p.lineId == leg.lineId &&
            (p.serviceId != null || p.towardsStationId != null) &&
            (p.serviceId == null || p.serviceId == leg.serviceId) &&
            (p.towardsStationId == null ||
                p.towardsStationId == leg.directionTerminalId))
          p,
    ];
    final numbers = {for (final p in rows) p.number};
    if (numbers.length != 1) return null;
    return PlatformInfo(
      number: rows.first.number,
      provenance: rows.first.provenance,
    );
  }

  /// Gates of [stationId] the data lists, by number; closed gates left out.
  static List<GateInfo> gatesAt(MetroSnapshot snapshot, String stationId) {
    final gates =
        snapshot.gatesAt(stationId).where((g) => g.isOpen != false).toList()
          ..sort((a, b) {
            final c = a.number.compareTo(b.number);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
    return List.unmodifiable([
      for (final g in gates)
        GateInfo(
          id: g.id,
          number: g.number,
          nameEn: g.nameEn,
          nameHi: g.nameHi,
          hasLift: g.hasLift,
          isStepFree: g.isStepFree,
          provenance: g.provenance,
          landmarksEn: [for (final l in snapshot.landmarksOf(g.id)) l.textEn],
          landmarksHi: [for (final l in snapshot.landmarksOf(g.id)) l.textHi],
        ),
    ]);
  }
}

/// Where the rider is. Immutable; every change returns a new state, so the
/// state can be saved and restored as plain JSON (resume after process
/// death). Times are milliseconds since the epoch, passed in by the caller
/// (no clock in here).
class JourneyState {
  const JourneyState({
    required this.stepIndex,
    required this.startedAtMs,
    required this.stepStartedAtMs,
    this.rideBaseIndex = 0,
  });

  /// A new journey at its first step.
  factory JourneyState.start(int nowMs) =>
      JourneyState(stepIndex: 0, startedAtMs: nowMs, stepStartedAtMs: nowMs);

  final int stepIndex;
  final int startedAtMs;

  /// When the current step began (for a ride: when the rider boarded, or the
  /// last time they said where they are).
  final int stepStartedAtMs;

  /// Ride: index into the ride's stations the time estimate counts from
  /// (0 = the boarding station; set by "I'm at (station)").
  final int rideBaseIndex;

  Map<String, Object> toJson() => {
    'step': stepIndex,
    'startedAtMs': startedAtMs,
    'stepStartedAtMs': stepStartedAtMs,
    'rideBase': rideBaseIndex,
  };

  /// Null when [json] is not a valid state.
  static JourneyState? fromJson(Object? json) {
    if (json is! Map) return null;
    final step = json['step'];
    final started = json['startedAtMs'];
    final stepStarted = json['stepStartedAtMs'];
    final base = json['rideBase'];
    if (step is! int ||
        started is! int ||
        stepStarted is! int ||
        base is! int) {
      return null;
    }
    if (step < 0 || base < 0) return null;
    return JourneyState(
      stepIndex: step,
      startedAtMs: started,
      stepStartedAtMs: stepStarted,
      rideBaseIndex: base,
    );
  }
}

/// Progress inside the current step, derived from the state and the clock.
class JourneyProgress {
  const JourneyProgress({
    required this.step,
    required this.stepIndex,
    required this.isLastStep,
    this.positionIndex,
    this.stopsRemaining,
    this.getOffNext = false,
    this.shouldBeThere = false,
  });

  final JourneyStep step;
  final int stepIndex;
  final bool isLastStep;

  /// Ride: estimated index into [JourneyStep.stationIds] of where the train
  /// is (never past the alighting station).
  final int? positionIndex;

  /// Ride: estimated stops still to go.
  final int? stopsRemaining;

  /// Ride: the next stop is where to get off (in-app alert).
  final bool getOffNext;

  /// Ride: by the estimate the train is at the alighting station.
  final bool shouldBeThere;
}

/// The journey step engine (docs/routing.md "Journey progress model").
///
/// - Position = max(time estimate, the rider's "I'm at (station)"); a
///   correction resets the estimate to start from that station.
/// - The estimate only moves the position **inside** the current ride. It
///   never moves to another step: getting off, changing and walking always
///   need the rider's confirmation (underground GPS is unreliable).
/// - Deterministic: same plan, state and time -> same progress.
class JourneyEngine {
  const JourneyEngine(this.plan);

  final JourneyPlan plan;

  /// Clamps a state to the plan (e.g. after a restore).
  JourneyState normalise(JourneyState s) {
    final i = s.stepIndex.clamp(0, plan.lastIndex);
    final step = plan.steps[i];
    final base = step.kind == JourneyStepKind.ride
        ? s.rideBaseIndex.clamp(0, step.stopCount)
        : 0;
    return JourneyState(
      stepIndex: i,
      startedAtMs: s.startedAtMs,
      stepStartedAtMs: s.stepStartedAtMs,
      rideBaseIndex: base,
    );
  }

  JourneyProgress progress(JourneyState state, int nowMs) {
    final s = normalise(state);
    final step = plan.steps[s.stepIndex];
    final last = s.stepIndex == plan.lastIndex;
    if (step.kind != JourneyStepKind.ride || step.stopCount == 0) {
      return JourneyProgress(
        step: step,
        stepIndex: s.stepIndex,
        isLastStep: last,
      );
    }
    final perStopMs = step.rideS * 1000 / step.stopCount;
    final elapsed = nowMs - s.stepStartedAtMs;
    final passed = perStopMs <= 0 || elapsed <= 0
        ? 0
        : (elapsed / perStopMs).floor();
    final pos = (s.rideBaseIndex + passed).clamp(
      s.rideBaseIndex,
      step.stopCount,
    );
    final remaining = step.stopCount - pos;
    return JourneyProgress(
      step: step,
      stepIndex: s.stepIndex,
      isLastStep: last,
      positionIndex: pos,
      stopsRemaining: remaining,
      getOffNext: remaining == 1,
      shouldBeThere: remaining == 0,
    );
  }

  /// The rider confirmed the current step ("I'm on the train", "I've
  /// changed", ...). Null when the journey is finished.
  JourneyState? advance(JourneyState state, int nowMs) {
    final s = normalise(state);
    if (s.stepIndex >= plan.lastIndex) return null;
    return JourneyState(
      stepIndex: s.stepIndex + 1,
      startedAtMs: s.startedAtMs,
      stepStartedAtMs: nowMs,
    );
  }

  /// Every station of the route the rider can say they are at, in route
  /// order, without repeats.
  List<String> correctableStations() {
    final out = <String>[];
    for (final (_, id, _) in _candidates()) {
      if (!out.contains(id)) out.add(id);
    }
    return List.unmodifiable(out);
  }

  /// "I'm at [stationId]": moves to the first place of the route at or after
  /// the current step where that station is, or (when it is only behind) to
  /// the last place before. Null when the station is not on the route.
  JourneyState? correctTo(JourneyState state, String stationId, int nowMs) {
    final s = normalise(state);
    final matches = [
      for (final c in _candidates())
        if (c.$2 == stationId) c,
    ];
    if (matches.isEmpty) return null;
    final ahead = matches.where((c) => c.$1 >= s.stepIndex);
    final (step, _, base) = ahead.isNotEmpty ? ahead.first : matches.last;
    return JourneyState(
      stepIndex: step,
      startedAtMs: s.startedAtMs,
      stepStartedAtMs: nowMs,
      rideBaseIndex: base,
    );
  }

  /// (step index, station id, ride base) for every station position of the
  /// route, in route order.
  Iterable<(int, String, int)> _candidates() sync* {
    for (var i = 0; i < plan.steps.length; i++) {
      final st = plan.steps[i];
      switch (st.kind) {
        case JourneyStepKind.ride:
          for (var k = 1; k < st.stationIds.length; k++) {
            yield (i, st.stationIds[k], k);
          }
        case JourneyStepKind.walk:
          yield (i, st.stationId, 0);
        case JourneyStepKind.enter:
        case JourneyStepKind.board:
        case JourneyStepKind.change:
        case JourneyStepKind.stayOnBoard:
        case JourneyStepKind.exit:
          yield (i, st.stationId, 0);
      }
    }
  }
}
