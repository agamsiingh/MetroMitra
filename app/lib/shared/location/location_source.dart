import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metromitra/shared/location/geolocator_location_source.dart';

/// Outcome of asking the device where it is. A position is held in memory by
/// the screen that asked and is never stored or sent anywhere.
sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  const LocationFix({
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.isApproximate = false,
  });

  final double lat;
  final double lng;

  /// Reported horizontal accuracy in metres; null = not reported.
  final double? accuracyM;

  /// A coarse grant, a last-known position, or a poor accuracy: the screen
  /// says the position is approximate.
  final bool isApproximate;
}

/// The user (or the system) said no. [permanent] = it will not be asked
/// again, so the only way forward is the system settings.
class LocationDenied extends LocationResult {
  const LocationDenied({this.permanent = false});

  final bool permanent;
}

/// No position could be obtained: location services are off, no fix within
/// the time limit and no last-known position, or the platform failed.
class LocationUnavailable extends LocationResult {
  const LocationUnavailable({this.servicesOff = false});

  /// Location services are switched off in the system settings.
  final bool servicesOff;
}

/// Seam for the platform location API (docs/testing.md: inject
/// `LocationSource`). Only the Nearby feature calls it, only after the user
/// asks, and a real implementation must not persist or transmit the result.
abstract interface class LocationSource {
  /// Asks for permission when needed, then returns the current position.
  Future<LocationResult> current();

  /// Live updates while listened to (map live tracking). Asks for permission
  /// like [current]; if that fails the stream emits one [LocationDenied] or
  /// [LocationUnavailable] and ends. A lost fix emits [LocationUnavailable]
  /// and the stream keeps going. Cancelling the subscription stops the GPS.
  Stream<LocationResult> watch();

  /// Opens the system settings of this app (to grant a denied permission).
  Future<void> openSettings();

  /// Opens the system location settings (to switch location services on).
  Future<void> openLocationSettings();
}

final locationSourceProvider = Provider<LocationSource>(
  (ref) => GeolocatorLocationSource(),
);
