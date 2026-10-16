import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:metro_core/metro_core.dart' hide Platform;

/// Why a dataset could not be used. Shown to the user as a plain-language
/// state, never as a raw exception.
enum DatasetProblem {
  /// No candidate file exists (nothing installed / bundled).
  missing,

  /// The file is not a readable dataset (damaged, truncated, not SQLite).
  corrupt,

  /// `schema_version` is outside the range this app build understands.
  incompatible,

  /// Readable but fails the dataset validation rules.
  invalid,

  /// A draft dataset (pipeline output with known gaps) in a build that does
  /// not allow drafts.
  draftNotAllowed,

  /// Synthetic TEST DATA in a build that does not allow it.
  testDataNotAllowed,
}

/// What this build may load. Release builds are always strict.
class DatasetPolicy {
  const DatasetPolicy({this.allowDraft = false, this.allowTestData = false});

  /// Reads the developer switches `--dart-define=METROMITRA_ALLOW_DRAFT=true`
  /// and `METROMITRA_ALLOW_TEST_DATA=true`. They are ignored in release mode.
  factory DatasetPolicy.fromEnvironment({required bool isReleaseMode}) {
    if (isReleaseMode) return strict;
    const draft = bool.fromEnvironment('METROMITRA_ALLOW_DRAFT');
    const testData = bool.fromEnvironment('METROMITRA_ALLOW_TEST_DATA');
    // The analyzer evaluates the defines as false; real builds may set them.
    // ignore: use_named_constants, avoid_redundant_argument_values
    return const DatasetPolicy(allowDraft: draft, allowTestData: testData);
  }

  /// Only `release` datasets that are not test data.
  static const strict = DatasetPolicy();

  final bool allowDraft;
  final bool allowTestData;
}

/// A place a dataset may be loaded from, tried in order.
class DatasetCandidate {
  const DatasetCandidate({required this.label, required this.path});

  /// Non-PII name used in logs and tests (`dev override`, `bundled`).
  final String label;
  final String path;
}

class DatasetAttempt {
  const DatasetAttempt(this.label, this.problem, this.detail);

  final String label;
  final DatasetProblem problem;
  final String detail;
}

sealed class BootstrapResult {
  const BootstrapResult();
}

final class BootstrapReady extends BootstrapResult {
  const BootstrapReady({
    required this.snapshot,
    required this.sourceLabel,
    this.skipped = const [],
  });

  final MetroSnapshot snapshot;
  final String sourceLabel;

  /// Earlier candidates that were rejected before this one worked.
  final List<DatasetAttempt> skipped;
}

final class BootstrapFailed extends BootstrapResult {
  const BootstrapFailed({required this.problem, required this.attempts});

  /// The problem of the first (highest-priority) candidate, or
  /// [DatasetProblem.missing] when there were none.
  final DatasetProblem problem;
  final List<DatasetAttempt> attempts;
}

/// Reads and validates a dataset file. May run in another isolate.
typedef DatasetLoader =
    FutureOr<MetroSnapshot> Function(String path, ValidationMode mode);

MetroSnapshot loadDatasetSync(String path, ValidationMode mode) =>
    DatasetReader.readFile(path, mode: mode);

/// Production loader: parsing and validating a dataset happens off the UI
/// isolate (docs/offline.md).
Future<MetroSnapshot> loadDatasetInIsolate(String path, ValidationMode mode) =>
    Isolate.run(() => DatasetReader.readFile(path, mode: mode));

/// Chooses the dataset to show the UI, deterministically and without network.
///
/// Candidates are tried in order; the first that loads *and* passes the
/// policy wins. A rejected candidate never reaches the UI. Nothing is
/// repaired, guessed or fabricated: with no usable candidate the result is a
/// [BootstrapFailed] naming the problem.
Future<BootstrapResult> bootstrapDataset({
  required List<DatasetCandidate> candidates,
  DatasetPolicy policy = DatasetPolicy.strict,
  DatasetLoader loader = loadDatasetSync,
}) async {
  final attempts = <DatasetAttempt>[];
  for (final c in candidates) {
    final attempt = await _tryCandidate(c, policy, loader);
    if (attempt is MetroSnapshot) {
      return BootstrapReady(
        snapshot: attempt,
        sourceLabel: c.label,
        skipped: attempts,
      );
    }
    attempts.add(attempt as DatasetAttempt);
  }
  return BootstrapFailed(
    problem: attempts.isEmpty ? DatasetProblem.missing : attempts.first.problem,
    attempts: attempts,
  );
}

/// Returns a [MetroSnapshot] or a [DatasetAttempt] describing the rejection.
Future<Object> _tryCandidate(
  DatasetCandidate c,
  DatasetPolicy policy,
  DatasetLoader loader,
) async {
  DatasetAttempt fail(DatasetProblem p, String detail) =>
      DatasetAttempt(c.label, p, detail);

  if (!File(c.path).existsSync()) {
    return fail(DatasetProblem.missing, 'no file');
  }
  final mode = policy.allowDraft
      ? ValidationMode.draft
      : ValidationMode.release;
  final MetroSnapshot snapshot;
  try {
    snapshot = await loader(c.path, mode);
  } on DatasetException catch (e) {
    return switch (e.failure) {
      DatasetFailure.incompatibleSchema => fail(
        DatasetProblem.incompatible,
        e.message,
      ),
      DatasetFailure.invalid
          when e.report?.hasError('draft-dataset') ?? false =>
        fail(DatasetProblem.draftNotAllowed, e.message),
      DatasetFailure.invalid => fail(DatasetProblem.invalid, e.message),
      DatasetFailure.unreadable ||
      DatasetFailure.malformed => fail(DatasetProblem.corrupt, e.message),
    };
  } on Object catch (e) {
    // SqliteException, FileSystemException, a crashed isolate...
    return fail(DatasetProblem.corrupt, '${e.runtimeType}');
  }
  if (snapshot.isDraft && !policy.allowDraft) {
    return fail(DatasetProblem.draftNotAllowed, 'meta.stage = draft');
  }
  if (snapshot.isTestData && !policy.allowTestData) {
    return fail(DatasetProblem.testDataNotAllowed, 'meta.is_test_data = true');
  }
  if (snapshot.stations.isEmpty) {
    return fail(DatasetProblem.invalid, 'no stations');
  }
  return snapshot;
}
