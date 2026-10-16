import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show AndroidSettings;
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:metromitra/shared/location/geolocator_location_source.dart';
import 'package:metromitra/shared/location/location_source.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

Position _pos(double lat, double lng, {double accuracy = 10}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.utc(2026, 10, 7),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// A scripted platform. `current == null` = the request never completes
/// (what was seen on an Android emulator).
class _FakePlatform extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  _FakePlatform({
    this.enabled = true,
    this.permission = LocationPermission.whileInUse,
    this.afterRequest = LocationPermission.whileInUse,
    this.current,
    this.currentError,
    this.last,
  });

  bool enabled;
  LocationPermission permission;
  LocationPermission afterRequest;
  Position? current;
  Object? currentError;
  Position? last;
  int requests = 0;
  LocationSettings? settings;
  bool? lastForcedManager;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return afterRequest;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    settings = locationSettings;
    if (currentError != null) return Future.error(currentError!);
    final c = current;
    return c == null ? Completer<Position>().future : Future.value(c);
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    lastForcedManager = forceLocationManager;
    return last;
  }
}

void main() {
  late GeolocatorPlatform original;
  setUp(() => original = GeolocatorPlatform.instance);
  tearDown(() {
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  _FakePlatform install(_FakePlatform p) {
    GeolocatorPlatform.instance = p;
    return p;
  }

  test('a fix is returned; precise unless poor accuracy', () async {
    install(_FakePlatform(current: _pos(28.6, 77.2)));
    final r = await GeolocatorLocationSource().current();
    expect(r, isA<LocationFix>());
    expect((r as LocationFix).isApproximate, isFalse);
    install(_FakePlatform(current: _pos(28.6, 77.2, accuracy: 5000)));
    final coarse = await GeolocatorLocationSource().current();
    expect((coarse as LocationFix).isApproximate, isTrue);
  });

  test('a request that never answers ends after the time limit (found on '
      'a device); last known position is used and called approximate', () {
    fakeAsync((async) {
      install(_FakePlatform(last: _pos(28.6, 77.2)));
      LocationResult? r;
      unawaited(GeolocatorLocationSource().current().then((v) => r = v));
      async.elapse(const Duration(seconds: 5));
      expect(r, isNull, reason: 'still waiting inside the time limit');
      async.elapse(const Duration(seconds: 10));
      expect(r, isA<LocationFix>());
      expect((r! as LocationFix).isApproximate, isTrue);
    });
  });

  test('no fix and no last known position: unavailable, never a hang', () {
    fakeAsync((async) {
      install(_FakePlatform());
      LocationResult? r;
      unawaited(GeolocatorLocationSource().current().then((v) => r = v));
      async.elapse(const Duration(seconds: 20));
      expect(r, isA<LocationUnavailable>());
    });
  });

  test('a platform error falls back to the last known position', () async {
    install(_FakePlatform(currentError: Exception('x')));
    expect(
      await GeolocatorLocationSource().current(),
      isA<LocationUnavailable>(),
    );
  });

  test('services off / denied / denied for good', () async {
    install(_FakePlatform(enabled: false));
    final off = await GeolocatorLocationSource().current();
    expect((off as LocationUnavailable).servicesOff, isTrue);

    final p = install(
      _FakePlatform(
        permission: LocationPermission.denied,
        afterRequest: LocationPermission.denied,
      ),
    );
    expect(await GeolocatorLocationSource().current(), isA<LocationDenied>());
    expect(p.requests, 1, reason: 'asked once, when the user tapped');

    install(_FakePlatform(permission: LocationPermission.deniedForever));
    final forever = await GeolocatorLocationSource().current();
    expect((forever as LocationDenied).permanent, isTrue);
  });

  test(
    'Android uses the platform LocationManager, not Play services',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final p = install(_FakePlatform(current: _pos(28.6, 77.2)));
      await GeolocatorLocationSource().current();
      expect(p.settings, isA<AndroidSettings>());
      expect((p.settings! as AndroidSettings).forceLocationManager, isTrue);
    },
  );
}
