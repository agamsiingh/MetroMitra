import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/shared/data/updater/dataset_store.dart';
import 'package:path_provider/path_provider.dart';

/// Path of the dataset bundled with the app (never a draft: the pipeline's
/// draft output is gitignored and `tools/check.dart` fails if it is bundled).
const bundledDatasetAsset = 'assets/data/metro.sqlite';

const _devDatasetPath = String.fromEnvironment('METROMITRA_DATASET');

final datasetPolicyProvider = Provider<DatasetPolicy>(
  (ref) => DatasetPolicy.fromEnvironment(isReleaseMode: kReleaseMode),
);

final datasetLoaderProvider = Provider<DatasetLoader>(
  (ref) => loadDatasetInIsolate,
);

/// `<appSupport>/datasets`, or null where there is no app storage (unit
/// tests without the plugin): then only override + bundled are used.
final datasetStoreProvider = FutureProvider<DatasetStore?>((ref) async {
  try {
    final dir = await getApplicationSupportDirectory();
    return DatasetStore(Directory('${dir.path}/datasets'));
  } on Object {
    return null;
  }
});

/// Candidates in priority order: a developer override path (debug/profile
/// only), the downloaded active dataset, the previous one, then the bundled
/// asset (docs/offline.md).
final datasetCandidatesProvider = FutureProvider<List<DatasetCandidate>>((
  ref,
) async {
  return [
    if (!kReleaseMode && _devDatasetPath.isNotEmpty)
      const DatasetCandidate(label: 'dev override', path: _devDatasetPath),
    ...?(await ref.watch(datasetStoreProvider.future))?.candidates(),
    ?await _bundledCandidate(),
  ];
});

Future<DatasetCandidate?> _bundledCandidate() async {
  final ByteData data;
  try {
    data = await rootBundle.load(bundledDatasetAsset);
  } on Object {
    return null; // nothing bundled
  }
  final dir = Directory('${Directory.systemTemp.path}/metromitra_dataset')
    ..createSync(recursive: true);
  final file = File('${dir.path}/bundled.sqlite');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (!file.existsSync() || file.lengthSync() != bytes.length) {
    file.writeAsBytesSync(bytes, flush: true);
  }
  return DatasetCandidate(label: 'bundled', path: file.path);
}

/// Loads and validates the dataset once per app run (retry = invalidate).
final bootstrapProvider = FutureProvider<BootstrapResult>((ref) async {
  final candidates = await ref.watch(datasetCandidatesProvider.future);
  final result = await bootstrapDataset(
    candidates: candidates,
    policy: ref.watch(datasetPolicyProvider),
    loader: ref.watch(datasetLoaderProvider),
  );
  // A downloaded dataset that passed the updater but fails here is marked bad
  // and the pointer falls back to the previous one (docs/offline.md).
  final skipped = switch (result) {
    BootstrapReady(:final skipped) => skipped,
    BootstrapFailed(:final attempts) => attempts,
  };
  final store = await ref.read(datasetStoreProvider.future);
  for (final a in skipped) {
    if (store != null &&
        a.label.startsWith('updated ') &&
        a.problem != DatasetProblem.missing) {
      store.markBad(a.label.substring('updated '.length));
    }
  }
  return result;
});

/// The engines built from the validated snapshot. Only read below the
/// bootstrap gate, which guarantees the dataset is ready.
final metroServicesProvider = Provider<MetroServices>((ref) {
  final result = ref.watch(bootstrapProvider).value;
  if (result is! BootstrapReady) {
    throw StateError('metroServicesProvider read before bootstrap succeeded');
  }
  return MetroServices(result.snapshot);
});
