import 'package:metro_core/src/model/enums.dart';

/// All money is integer paise.
class FareSystem {
  const FareSystem({
    required this.id,
    required this.operatorId,
    required this.currency,
    required this.effectiveFrom,
    required this.sourceId,
  });

  final String id;
  final String operatorId;
  final String currency;

  /// ISO date.
  final String effectiveFrom;
  final String sourceId;
}

/// Distance band `[minKm, maxKm)`; `maxKm == null` is the open-ended last band.
class FareSlab {
  const FareSlab({
    required this.fareSystemId,
    required this.dayType,
    required this.minKm,
    required this.maxKm,
    required this.amountPaise,
  });

  final String fareSystemId;
  final DayType dayType;
  final int minKm;
  final int? maxKm;
  final int amountPaise;
}

class FareDiscount {
  const FareDiscount({
    required this.fareSystemId,
    required this.media,
    required this.kind,
    required this.percent,
    this.windowsJson,
  });

  final String fareSystemId;
  final FareMedia media;
  final FareDiscountKind kind;
  final int percent;

  /// JSON list of `{days, from, to}` windows for off-peak discounts.
  final String? windowsJson;
}

/// Verified fare for a station pair that wins over the computed slab fare.
class FareOverride {
  const FareOverride({
    required this.fareSystemId,
    required this.fromStation,
    required this.toStation,
    required this.dayType,
    required this.amountPaise,
    required this.sourceId,
    required this.verifiedOn,
  });

  final String fareSystemId;
  final String fromStation;
  final String toStation;
  final DayType dayType;
  final int amountPaise;
  final String sourceId;
  final String verifiedOn;
}
