import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/app.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';

import 'support/app_harness.dart';
import 'support/test_network.dart';

const _fixture = '../data/fixtures/mini_network/dataset.yaml';

void main() {
  group('failure states (nothing from a bad dataset reaches the UI)', () {
    final cases = {
      DatasetProblem.missing: ('No metro data installed', 'Try again'),
      DatasetProblem.corrupt: ("Metro data can't be read", 'Try again'),
      DatasetProblem.incompatible: (
        'Metro data needs another app version',
        'Try again',
      ),
      DatasetProblem.invalid: ('Metro data failed its checks', 'Try again'),
      DatasetProblem.draftNotAllowed: ('Draft data not allowed', 'Try again'),
      DatasetProblem.testDataNotAllowed: (
        'Test data not allowed',
        'Try again',
      ),
    };
    for (final e in cases.entries) {
      testWidgets('${e.key.name}: explained in plain words, no app shell', (
        tester,
      ) async {
        await pumpApp(
          tester,
          result: BootstrapFailed(problem: e.key, attempts: const []),
        );
        expect(key('boot-failure-${e.key.name}'), findsOneWidget);
        expect(find.text(e.value.$1), findsOneWidget);
        expect(find.text(e.value.$2), findsOneWidget);
        // no tabs, no home screen, no station data
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('Where do you want to go?'), findsNothing);
      });
    }

    testWidgets('Hindi interface translates the failure', (tester) async {
      await pumpApp(
        tester,
        locale: const Locale('hi'),
        result: const BootstrapFailed(
          problem: DatasetProblem.missing,
          attempts: [],
        ),
      );
      expect(find.text('मेट्रो डेटा इंस्टॉल नहीं है'), findsOneWidget);
    });

    testWidgets('an unexpected error while starting is shown as corrupt', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 3200)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [
          bootstrapProvider.overrideWith((ref) => throw StateError('boom')),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MetroMitraApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(key('boot-failure-corrupt'), findsOneWidget);
    });
  });

  group('loading and retry', () {
    testWidgets('a loading state shows until the dataset is ready', (
      tester,
    ) async {
      final completer = Completer<BootstrapResult>();
      final c = ProviderContainer(
        overrides: [bootstrapProvider.overrideWith((ref) => completer.future)],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MetroMitraApp(),
        ),
      );
      await tester.pump();
      expect(key('boot-loading'), findsOneWidget);
      expect(find.text('Loading metro data…'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      completer.complete(
        BootstrapReady(snapshot: demoNetwork(), sourceLabel: 'test'),
      );
      await tester.pumpAndSettle();
      expect(key('boot-loading'), findsNothing);
      expect(key('home-tile-route'), findsOneWidget);
    });

    testWidgets('Try again re-runs bootstrap and recovers', (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 3200)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          bootstrapProvider.overrideWith((ref) async {
            calls++;
            return calls == 1
                ? const BootstrapFailed(
                    problem: DatasetProblem.corrupt,
                    attempts: [],
                  )
                : BootstrapReady(snapshot: demoNetwork(), sourceLabel: 'test');
          }),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MetroMitraApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(key('boot-failure-corrupt'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(key('home-tile-route'), findsOneWidget);
    });
  });

  group('end to end through a real SQLite file', () {
    late Directory tmp;
    late String path;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('gate_test_');
      path = '${tmp.path}/metro.sqlite';
      DatasetWriter.writeFile(YamlDatasetLoader.loadFile(_fixture), path);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<ProviderContainer> pumpReal(
      WidgetTester tester, {
      DatasetPolicy policy = const DatasetPolicy(allowTestData: true),
      String? file,
    }) async {
      tester.view
        ..physicalSize = const Size(1200, 3200)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [
          datasetStoreProvider.overrideWith((ref) => null),
          datasetCandidatesProvider.overrideWith(
            (ref) => [DatasetCandidate(label: 'file', path: file ?? path)],
          ),
          datasetPolicyProvider.overrideWithValue(policy),
          datasetLoaderProvider.overrideWithValue(loadDatasetSync),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MetroMitraApp(),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('loads the dataset file, searches it and routes on it', (
      tester,
    ) async {
      final c = await pumpReal(tester);
      expect(key('home-tile-route'), findsOneWidget);
      expect(
        find.text('TEST DATA — not real metro information.'),
        findsOneWidget,
      );

      await tester.tap(key('home-tile-route'));
      await tester.pumpAndSettle();
      await pickStation(tester, JourneyEnd.from, 'test alpha', 'test-alpha');
      await pickStation(tester, JourneyEnd.to, 'test iota', 'test-iota');
      expect(selection(c).fromId, 'test-alpha');
      expect(selection(c).toId, 'test-iota');
      await tester.tap(key('find-route'));
      await tester.pumpAndSettle();
      expect(key('route-found'), findsOneWidget);
      expect(find.text('Change at TEST Gamma (Interchange)'), findsOneWidget);
      // the fixture carries TEST fare data: a fare is shown only because it exists
      expect(key('fare-available'), findsOneWidget);
    });

    testWidgets('a strict build refuses the TEST DATA file', (tester) async {
      await pumpReal(tester, policy: DatasetPolicy.strict);
      expect(key('boot-failure-testDataNotAllowed'), findsOneWidget);
    });

    testWidgets('a missing file is reported as missing', (tester) async {
      await pumpReal(tester, file: '${tmp.path}/gone.sqlite');
      expect(key('boot-failure-missing'), findsOneWidget);
    });

    testWidgets('a damaged file is reported as unreadable', (tester) async {
      File(path).writeAsBytesSync(List.generate(300, (i) => i % 200));
      await pumpReal(tester);
      expect(key('boot-failure-corrupt'), findsOneWidget);
    });
  });
}
