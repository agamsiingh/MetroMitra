import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/map/application/map_provider.dart';
import 'package:metromitra/shared/location/location_source.dart';

/// Farthest a station may be to be called "nearest" on the map.
const trackingNearestRadiusM = 30000.0;

/// Live position on the map. Held in memory only, for as long as the map is
/// open and tracking is on (docs/security.md: never stored or sent).
sealed class TrackingState {
  const TrackingState();
}

final class TrackingOff extends TrackingState {
  const TrackingOff();
}

/// Waiting for permission or the first fix.
final class TrackingStarting extends TrackingState {
  const TrackingStarting();
}

final class TrackingOn extends TrackingState {
  const TrackingOn({
    required this.fix,
    required this.point,
    required this.nearest,
    required this.frame,
    this.lost = false,
  });

  final LocationFix fix;

  /// The position in the map plane; null when it cannot be drawn.
  final (double, double)? point;

  /// Closest open station within [trackingNearestRadiusM], straight line.
  final NearbyStation? nearest;

  /// Framing chosen at the first fix (you + nearest station). Kept for the
  /// whole session, so later updates move the dot, not the camera.
  final MapRect? frame;

  /// The fix was lost after this position; still trying.
  final bool lost;
}

final class TrackingDenied extends TrackingState {
  const TrackingDenied({required this.permanent});

  final bool permanent;
}

final class TrackingUnavailable extends TrackingState {
  const TrackingUnavailable({required this.servicesOff});

  final bool servicesOff;
}

class LiveTracking extends Notifier<TrackingState> {
  StreamSubscription<LocationResult>? _sub;

  @override
  TrackingState build() {
    ref.onDispose(() => unawaited(_sub?.cancel()));
    return const TrackingOff();
  }

  bool get isActive => state is TrackingStarting || state is TrackingOn;

  void toggle() => isActive ? stop() : start();

  void start() {
    unawaited(_sub?.cancel());
    state = const TrackingStarting();
    _sub = ref.read(locationSourceProvider).watch().listen(_onResult);
  }

  void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
    state = const TrackingOff();
  }

  void _onResult(LocationResult r) {
    final previous = state;
    switch (r) {
      case LocationFix():
        final geometry = ref.read(mapGeometryProvider);
        final services = ref.read(metroServicesProvider);
        final point = geometry.project(r.lat, r.lng);
        final nearest = findNearbyStations(
          services.snapshot.stations,
          lat: r.lat,
          lng: r.lng,
          maxDistanceM: trackingNearestRadiusM,
          limit: 1,
        );
        final near = nearest.isEmpty ? null : nearest.first;
        final frame = previous is TrackingOn
            ? previous.frame
            : geometry.framingWith(
                [?near?.station.id],
                [?point],
              );
        state = TrackingOn(
          fix: r,
          point: point,
          nearest: near,
          frame: frame,
        );
      case LocationDenied(:final permanent):
        stop();
        state = TrackingDenied(permanent: permanent);
      case LocationUnavailable(:final servicesOff):
        if (previous is TrackingOn && !servicesOff) {
          // keep the last position on screen, marked as lost
          state = TrackingOn(
            fix: previous.fix,
            point: previous.point,
            nearest: previous.nearest,
            frame: previous.frame,
            lost: true,
          );
        } else {
          stop();
          state = TrackingUnavailable(servicesOff: servicesOff);
        }
    }
  }
}

/// Auto-disposed: leaving the map cancels the GPS subscription.
final liveTrackingProvider =
    NotifierProvider.autoDispose<LiveTracking, TrackingState>(
      LiveTracking.new,
    );
