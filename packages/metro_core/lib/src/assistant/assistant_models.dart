import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/provenance.dart';

/// What the question is about (docs/ai.md "Intents (V1)").
enum AssistantIntent {
  route,
  nearestStation,
  gateExit,
  platform,
  fare,
  firstLast,
  interchange,
  facilities,
  accessibility,
  parking,
  lineInfo,
  unknown,
}

enum AnswerKind {
  /// Facts from the dataset.
  answer,

  /// The dataset has no verified fact for this ("I don't have ... yet").
  missing,

  /// A slot is ambiguous or missing: ask, with chips or a station picker.
  clarify,

  /// A named place is not in the dataset.
  notFound,

  /// Not something the offline assistant answers.
  unknown,
}

/// Every answer the assistant can give. The app renders each one from a
/// localized template and the answer's facts only: there is no free text,
/// so nothing can be said that the dataset does not hold (docs/ai.md
/// "No-fabrication guarantee").
enum AnswerTemplate {
  routeSummary,
  routeSameStation,
  routeNone,
  nearestOpen,
  gatesList,
  gateForLandmark,
  gateLandmarkUnknown,
  gatesMissing,
  platformFound,
  platformMissing,
  fareFound,
  fareMissing,
  firstLastFound,
  firstLastMissing,
  interchangeNone,
  interchangeAt,
  facilitiesList,
  facilityFound,
  facilityMissing,
  accessibilityFound,
  accessibilityMissing,
  parkingMissing,
  lineInfo,
  stationNotFound,
  clarifyStation,
  askFrom,
  askTo,
  askStation,
  askDestination,
  unknown,
}

/// Slots a clarification can fill.
enum AssistantSlot { from, to, station, destination }

/// Something the user can do from an answer (no action is ever taken by the
/// assistant itself).
sealed class AssistantAction {
  const AssistantAction();
}

class OpenRouteAction extends AssistantAction {
  const OpenRouteAction(this.fromId, this.toId);

  final String fromId;
  final String toId;
}

class OpenStationAction extends AssistantAction {
  const OpenStationAction(this.stationId);

  final String stationId;
}

class OpenNearbyAction extends AssistantAction {
  const OpenNearbyAction();
}

/// Ask the user to pick a station for [slot] (the app opens its picker).
class PickStationAction extends AssistantAction {
  const PickStationAction(this.slot);

  final AssistantSlot slot;
}

/// A first/last departure the dataset has, for one direction and day type.
class TimingFact {
  const TimingFact({
    required this.terminalId,
    required this.serviceId,
    required this.dayType,
    required this.firstDep,
    required this.lastDep,
    required this.provenance,
  });

  final String terminalId;
  final String serviceId;
  final DayType dayType;

  /// Minutes since 00:00 of the service day (may exceed 1440).
  final int firstDep;
  final int lastDep;
  final Provenance provenance;
}

/// The question understood: intent and slots (canonical ids only). An
/// answer that asks for clarification carries it so the app can fill the
/// slot and ask again.
class ParsedQuestion {
  const ParsedQuestion({
    required this.intent,
    this.fromId,
    this.toId,
    this.stationId,
    this.destinationId,
    this.lineId,
    this.facility,
    this.landmark,
    this.wantsFirst = false,
    this.wantsLast = false,
    this.wantsCard = false,
  });

  final AssistantIntent intent;
  final String? fromId;
  final String? toId;
  final String? stationId;
  final String? destinationId;
  final String? lineId;
  final FacilityType? facility;

  /// Free text of a place near a gate the user asked about (matched against
  /// the dataset's gate landmarks only).
  final String? landmark;
  final bool wantsFirst;
  final bool wantsLast;
  final bool wantsCard;

  ParsedQuestion withSlot(AssistantSlot slot, String stationId) =>
      ParsedQuestion(
        intent: intent,
        fromId: slot == AssistantSlot.from ? stationId : fromId,
        toId: slot == AssistantSlot.to ? stationId : toId,
        stationId: slot == AssistantSlot.station ? stationId : this.stationId,
        destinationId: slot == AssistantSlot.destination
            ? stationId
            : destinationId,
        lineId: lineId,
        facility: facility,
        landmark: landmark,
        wantsFirst: wantsFirst,
        wantsLast: wantsLast,
        wantsCard: wantsCard,
      );

  @override
  String toString() =>
      'ParsedQuestion(${intent.name}, from=$fromId, to=$toId, '
      'station=$stationId, dest=$destinationId, line=$lineId, '
      'facility=${facility?.name}, landmark=$landmark)';
}

class AssistantAnswer {
  const AssistantAnswer({
    required this.intent,
    required this.kind,
    required this.template,
    required this.datasetVersion,
    this.facts = const {},
    this.sources = const [],
    this.actions = const [],
    this.choices = const [],
    this.slot,
    this.question,
  });

  final AssistantIntent intent;
  final AnswerKind kind;
  final AnswerTemplate template;

  /// Typed values from the dataset, keyed by name (documented per template
  /// in `assistant.dart`). Station / line values are canonical ids.
  final Map<String, Object> facts;

  /// Provenance of the facts used.
  final List<Provenance> sources;
  final String datasetVersion;
  final List<AssistantAction> actions;

  /// Clarify: candidate station ids for [slot].
  final List<String> choices;
  final AssistantSlot? slot;

  /// Clarify: the question to complete with [ParsedQuestion.withSlot].
  final ParsedQuestion? question;

  T fact<T extends Object>(String key) => facts[key]! as T;
  T? factOrNull<T extends Object>(String key) => facts[key] as T?;
}
