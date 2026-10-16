import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/shared/format/format.dart';

/// "Now" for fare day type and off-peak windows; overridable in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

sealed class RouteLookup {
  const RouteLookup();
}

/// One or more alternatives, best first.
final class RouteFound extends RouteLookup {
  const RouteFound(this.options);

  final List<RouteOption> options;
}

final class RouteSameStation extends RouteLookup {
  const RouteSameStation();
}

/// An id that is not in the dataset (stale link / bad input).
final class RouteUnknownStation extends RouteLookup {
  const RouteUnknownStation(this.stationId);

  final String stationId;
}

/// The station exists but no open service stops there.
final class RouteNotServed extends RouteLookup {
  const RouteNotServed(this.stationId);

  final String stationId;
}

/// Both stations are served but the data has no path between them.
final class RouteUnreachable extends RouteLookup {
  const RouteUnreachable(this.fromId, this.toId);

  final String fromId;
  final String toId;
}

/// An itinerary plus the optional smart-card fare (only when the dataset has
/// smart-card discounts; the itinerary's own fare is the token fare).
class RouteOption {
  const RouteOption({required this.itinerary, this.cardFare});

  final Itinerary itinerary;
  final FareQuote? cardFare;
}

@immutable
class RouteQuery {
  const RouteQuery(this.fromId, this.toId);

  final String fromId;
  final String toId;

  @override
  bool operator ==(Object other) =>
      other is RouteQuery && other.fromId == fromId && other.toId == toId;

  @override
  int get hashCode => Object.hash(fromId, toId);
}

/// Plans a journey with the M3 router. Pure and synchronous (the graph is
/// small); never invents a station, route or fare.
final routeLookupProvider = Provider.family<RouteLookup, RouteQuery>((
  ref,
  query,
) {
  final services = ref.watch(metroServicesProvider);
  final now = ref.watch(clockProvider)();
  final request = FareRequest(
    dayType: dayTypeOf(now),
    minuteOfDay: now.hour * 60 + now.minute,
  );
  final result = services.planner.plan(
    query.fromId,
    query.toId,
    fareRequest: request,
  );
  final hasCardDiscount = services.snapshot.fareDiscounts.any(
    (d) => d.media == FareMedia.smartCard,
  );
  return switch (result.status) {
    RouteStatus.ok => RouteFound([
      for (final it in result.itineraries)
        RouteOption(
          itinerary: it,
          cardFare: hasCardDiscount
              ? services.fares.quote(
                  it.legs,
                  FareRequest(
                    dayType: request.dayType,
                    media: FareMedia.smartCard,
                    minuteOfDay: request.minuteOfDay,
                  ),
                )
              : null,
        ),
    ]),
    RouteStatus.sameStation => const RouteSameStation(),
    RouteStatus.unknownStation => RouteUnknownStation(result.detail ?? ''),
    RouteStatus.notServed => RouteNotServed(result.detail ?? ''),
    RouteStatus.noRoute => RouteUnreachable(query.fromId, query.toId),
  };
});
