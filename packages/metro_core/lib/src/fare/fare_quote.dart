import 'package:metro_core/src/model/enums.dart';

/// Why a fare could not be computed. Fares are never guessed.
enum FareGap {
  /// Operator has no fare system in the dataset.
  noFareSystem,

  /// No slab covers the distance / day type.
  noSlab,

  /// The two stations are not connected inside the operator's own network.
  noDistance,

  /// A discount window in the dataset could not be read.
  badDiscountWindow,
}

/// How a segment's listed (pre-discount) fare was obtained.
enum FareBasis {
  /// A verified station-pair `fare_override`.
  override,

  /// Slab for the shortest in-network distance.
  slab,
}

/// One ticket: a run of rides on one operator without leaving the paid area.
class FareSegment {
  const FareSegment({
    required this.operatorId,
    required this.fromStationId,
    required this.toStationId,
    this.fareSystemId,
    this.distanceM,
    this.basis,
    this.listedPaise,
    this.amountPaise,
    this.discountPercent = 0,
    this.appliedDiscounts = const [],
    this.confidence,
    this.sourceId,
    this.gap,
    this.notes = const [],
  });

  final String operatorId;
  final String fromStationId;
  final String toStationId;
  final String? fareSystemId;

  /// Shortest in-network distance used for the slab (derived data).
  final int? distanceM;
  final FareBasis? basis;

  /// Fare before discounts.
  final int? listedPaise;

  /// Final fare in paise; null when [gap] is set.
  final int? amountPaise;
  final int discountPercent;
  final List<String> appliedDiscounts;
  final Confidence? confidence;

  /// Source of the fare table / override.
  final String? sourceId;
  final FareGap? gap;
  final List<String> notes;

  bool get priced => amountPaise != null;
}

enum FareStatus { available, partial, unavailable }

/// Fare for a whole itinerary. All money is integer paise.
class FareQuote {
  const FareQuote({
    required this.status,
    required this.segments,
    required this.separateTicket,
    this.totalPaise,
    this.currency,
    this.confidence,
    this.notes = const [],
  });

  /// Nothing to price (no ride legs).
  const FareQuote.none()
    : status = FareStatus.unavailable,
      segments = const [],
      separateTicket = false,
      totalPaise = null,
      currency = null,
      confidence = null,
      notes = const ['no ride legs'];

  final FareStatus status;
  final List<FareSegment> segments;

  /// More than one ticket is needed (operator change or leaving the paid area).
  final bool separateTicket;

  /// null unless every segment is priced.
  final int? totalPaise;
  final String? currency;

  /// Weakest confidence among the segments.
  final Confidence? confidence;
  final List<String> notes;

  bool get isAvailable => status == FareStatus.available;
}

/// What the rider is paying with and when.
class FareRequest {
  const FareRequest({
    this.dayType = DayType.regular,
    this.media = FareMedia.token,
    this.minuteOfDay,
  });

  final DayType dayType;
  final FareMedia media;

  /// Minutes since 00:00 of the service day; null = unknown (off-peak
  /// discounts are then not applied and a note says so).
  final int? minuteOfDay;
}
