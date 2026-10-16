import 'package:metro_core/src/dataset/dataset_reader.dart';
import 'package:metro_core/src/model/snapshot.dart';

/// Source of the metro dataset. The app depends on this, never on SQLite.
///
/// Two implementations exist today (hence an interface, per
/// docs/architecture.md): SQLite file and in-memory (tests, tools).
abstract interface class DatasetRepository {
  /// Loads and validates the dataset. Throws [DatasetException] if it cannot
  /// be used; callers fall back (offline.md fallback chain).
  Future<MetroSnapshot> load();
}

/// Reads a `metro.sqlite` file (bundled asset copy or downloaded update).
class SqliteDatasetRepository implements DatasetRepository {
  const SqliteDatasetRepository(this.path);

  final String path;

  @override
  Future<MetroSnapshot> load() async => DatasetReader.readFile(path);
}

/// Serves an already built snapshot.
class InMemoryDatasetRepository implements DatasetRepository {
  const InMemoryDatasetRepository(this.snapshot);

  final MetroSnapshot snapshot;

  @override
  Future<MetroSnapshot> load() async => snapshot;
}
