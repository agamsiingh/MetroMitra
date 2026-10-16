import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:metromitra/shared/location/location_source.dart';

/// The device's own location services via the platform plugin: no network
/// location provider of ours, no external API, nothing stored.
class GeolocatorLocationSource implements LocationSource {
  /// How long to wait for a fix before using the last known position
  /// (docs/security.md: 10 s).
  static const timeout = Duration(seconds: 10);

  /// How long the last known position may take to read.
  static const lastKnownTimeout = Duration(seconds: 3);

  /// Above this reported accuracy a position is called approximate.
  static const approximateAboveM = 1000.0;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  /// On Android the platform `LocationManager` is used, not Google Play
  /// services: no extra "location accuracy" dialog (found on a device: saying
  /// "No thanks" there failed the request although GPS had a fix) and no
  /// dependency on a Google service.
  LocationSettings get _settings => _android
      ? AndroidSettings(forceLocationManager: true, timeLimit: timeout)
      : const LocationSettings(timeLimit: timeout);

  /// Live tracking: an update after moving this far (metres).
  static const trackingDistanceFilterM = 10;

  /// Permission and services check shared by [current] and [watch]; null
  /// when a position may be requested.
  Future<LocationResult?> _ready() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationUnavailable(servicesOff: true);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationDenied(permanent: true);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      return const LocationDenied();
    }
    return null;
  }

  @override
  Stream<LocationResult> watch() async* {
    final LocationResult? blocked;
    try {
      blocked = await _ready();
    } on Object {
      yield const LocationUnavailable();
      return;
    }
    if (blocked != null) {
      yield blocked;
      return;
    }
    final settings = _android
        ? AndroidSettings(
            forceLocationManager: true,
            distanceFilter: trackingDistanceFilterM,
          )
        : const LocationSettings(distanceFilter: trackingDistanceFilterM);
    yield* Geolocator.getPositionStream(locationSettings: settings)
        .map<LocationResult>((p) => _fix(p, lastKnown: false))
        .transform(
          StreamTransformer<LocationResult, LocationResult>.fromHandlers(
            handleError: (e, s, sink) => sink.add(
              e is LocationServiceDisabledException
                  ? const LocationUnavailable(servicesOff: true)
                  : const LocationUnavailable(),
            ),
          ),
        );
  }

  @override
  Future<LocationResult> current() async {
    try {
      final blocked = await _ready();
      if (blocked != null) return blocked;
      // The plugin's own time limit did not fire on a device (the request
      // hung for over 40 s), so the limit is also enforced here.
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: _settings,
        ).timeout(timeout + const Duration(seconds: 1));
        return _fix(p, lastKnown: false);
      } on Object {
        final last = await Geolocator.getLastKnownPosition(
          forceAndroidLocationManager: _android,
        ).timeout(lastKnownTimeout, onTimeout: () => null);
        return last == null
            ? const LocationUnavailable()
            : _fix(last, lastKnown: true);
      }
    } on Object {
      return const LocationUnavailable();
    }
  }

  LocationFix _fix(Position p, {required bool lastKnown}) => LocationFix(
    lat: p.latitude,
    lng: p.longitude,
    accuracyM: p.accuracy,
    isApproximate: lastKnown || p.accuracy > approximateAboveM,
  );

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
