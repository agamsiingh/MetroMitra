import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/app.dart';
import 'package:metromitra/app/router.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/go/application/route_lookup.dart';
import 'package:metromitra/features/remote_config/application/remote_config_providers.dart';
import 'package:metromitra/shared/data/journey_store.dart';
import 'package:metromitra/shared/data/keep_awake.dart';
import 'package:metromitra/shared/location/location_source.dart';

import 'test_network.dart';

/// A Monday at noon: a regular fare day, outside the off-peak window.
final monday = DateTime(2026, 10, 5, 12);
final sunday = DateTime(2026, 10, 4, 12);

/// Pumps the whole app with a ready (invented) dataset instead of a file.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  MetroSnapshot? snapshot,
  BootstrapResult? result,
  DateTime? now,
  Locale? locale,
  String? location,
  LocationSource? locationSource,
  List<Override> extraOverrides = const [],
  JourneyStore? journeyStore,
  KeepAwake? keepAwake,
  DateTime Function()? clock,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 3200)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  if (locale != null) {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
  final container = ProviderContainer(
    overrides: [
      datasetStoreProvider.overrideWith((ref) => null),
      remoteConfigFileProvider.overrideWith((ref) => null),
      bootstrapProvider.overrideWith(
        (ref) async =>
            result ??
            BootstrapReady(
              snapshot: snapshot ?? demoNetwork(),
              sourceLabel: 'test',
            ),
      ),
      clockProvider.overrideWithValue(clock ?? () => now ?? monday),
      if (locationSource != null)
        locationSourceProvider.overrideWithValue(locationSource),
      journeyStoreProvider.overrideWithValue(
        journeyStore ?? MemoryJourneyStore(),
      ),
      keepAwakeProvider.overrideWithValue(keepAwake ?? FakeKeepAwake()),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MetroMitraApp(),
    ),
  );
  await tester.pumpAndSettle();
  // The app opens on the Home grid; most tests exercise the planner, so they
  // start on /go unless a location is given.
  container.read(routerProvider).go(location ?? Routes.go);
  await tester.pumpAndSettle();
  return container;
}

Finder key(String k) => find.byKey(Key(k));

/// Chooses [id] for [end] through the real picker UI.
Future<void> pickStation(
  WidgetTester tester,
  JourneyEnd end,
  String query,
  String id,
) async {
  await tester.tap(key('field-${end.name}'));
  await tester.pumpAndSettle();
  await tester.enterText(key('picker-field'), query);
  await tester.pumpAndSettle();
  await tester.tap(key('station-option-$id'));
  await tester.pumpAndSettle();
}

JourneySelection selection(ProviderContainer c) => c.read(journeyProvider);

GoRouter routerOf(ProviderContainer c) => c.read(routerProvider);

/// A scripted [LocationSource]: returns [result] and records what was asked.
class FakeLocationSource implements LocationSource {
  FakeLocationSource(this.result);

  LocationResult result;
  int calls = 0;
  int settingsOpened = 0;
  int locationSettingsOpened = 0;

  @override
  Future<LocationResult> current() async {
    calls++;
    return result;
  }

  /// Live updates: tests push results into [live].
  final live = StreamController<LocationResult>.broadcast();
  int watchers = 0;

  @override
  Stream<LocationResult> watch() {
    watchers++;
    return live.stream;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> openLocationSettings() async => locationSettingsOpened++;
}

/// In-memory [JourneyStore] for tests; survives a re-pumped app when the
/// same instance is passed again ("process death").
class MemoryJourneyStore implements JourneyStore {
  String? saved;
  int? savedAtMs;
  int saves = 0;
  bool failSaves = false;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String json, int savedAtMs) async {
    if (failSaves) throw StateError('disk full');
    saves++;
    saved = json;
    this.savedAtMs = savedAtMs;
  }

  @override
  Future<void> clear() async => saved = null;
}

/// Records keep-awake requests.
class FakeKeepAwake implements KeepAwake {
  final calls = <bool>[];

  bool get isOn => calls.isNotEmpty && calls.last;

  @override
  Future<void> set({required bool on}) async => calls.add(on);
}
