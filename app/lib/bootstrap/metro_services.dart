import 'package:metro_core/metro_core.dart' hide Platform;

/// Everything the UI needs from the dataset, built once after bootstrap:
/// the immutable snapshot plus the pure-Dart search and routing engines.
/// The app only uses metro_core's public API.
class MetroServices {
  MetroServices(this.snapshot)
    : search = SearchIndex.fromSnapshot(snapshot),
      fares = FareEngine(snapshot) {
    planner = RoutePlanner(snapshot, fareEngine: fares);
    assistant = OfflineAssistant(
      snapshot: snapshot,
      search: search,
      planner: planner,
      fares: fares,
    );
  }

  final MetroSnapshot snapshot;
  final SearchIndex search;
  final FareEngine fares;
  late final RoutePlanner planner;

  /// The offline assistant (M9): deterministic, over the same services.
  late final OfflineAssistant assistant;

  String get datasetVersion => snapshot.datasetVersion ?? '';
  bool get isDraft => snapshot.isDraft;
  bool get isTestData => snapshot.isTestData;
}
