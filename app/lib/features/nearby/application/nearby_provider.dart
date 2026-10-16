import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/go/application/station_options.dart';
import 'package:metromitra/shared/location/location_source.dart';

class NearbyRow {
  const NearbyRow({required this.option, required this.distanceM});

  /// Display data (names, lines) of a station; [StationOption.id] is canonical.
  final StationOption option;

  /// Straight-line distance in metres. Not a walking distance.
  final int distanceM;
}

sealed class NearbyState {
  const NearbyState();
}

/// Nothing asked yet: the screen explains why location is needed first.
class NearbyIdle extends NearbyState {
  const NearbyIdle();
}

class NearbyLocating extends NearbyState {
  const NearbyLocating();
}

class NearbyDenied extends NearbyState {
  const NearbyDenied({required this.permanent});

  final bool permanent;
}

class NearbyUnavailable extends NearbyState {
  const NearbyUnavailable({required this.servicesOff});

  final bool servicesOff;
}

/// The device returned a position that cannot be used (not finite, out of
/// range, or the 0,0 "no fix" value).
class NearbyInvalidLocation extends NearbyState {
  const NearbyInvalidLocation();
}

/// A usable position; [rows] may be empty (no station within the radius).
class NearbyReady extends NearbyState {
  const NearbyReady({required this.rows, required this.isApproximate});

  final List<NearbyRow> rows;
  final bool isApproximate;
}

/// Holds the result in memory only; leaving the screen disposes it, so a
/// position is never kept, stored or sent.
class NearbyController extends Notifier<NearbyState> {
  @override
  NearbyState build() => const NearbyIdle();

  Future<void> locate() async {
    if (state is NearbyLocating) return;
    state = const NearbyLocating();
    final result = await ref.read(locationSourceProvider).current();
    if (!ref.mounted) return;
    state = switch (result) {
      LocationDenied(:final permanent) => NearbyDenied(permanent: permanent),
      LocationUnavailable(:final servicesOff) => NearbyUnavailable(
        servicesOff: servicesOff,
      ),
      LocationFix() => _resolve(result),
    };
  }

  NearbyState _resolve(LocationFix fix) {
    if (!isValidCoordinate(fix.lat, fix.lng)) {
      return const NearbyInvalidLocation();
    }
    final services = ref.read(metroServicesProvider);
    final found = findNearbyStations(
      services.snapshot.stations,
      lat: fix.lat,
      lng: fix.lng,
    );
    return NearbyReady(
      isApproximate: fix.isApproximate,
      rows: [
        for (final n in found)
          NearbyRow(
            option: stationOptionFor(services, n.station.id)!,
            distanceM: n.distanceM,
          ),
      ],
    );
  }
}

final nearbyProvider =
    NotifierProvider.autoDispose<NearbyController, NearbyState>(
      NearbyController.new,
    );
