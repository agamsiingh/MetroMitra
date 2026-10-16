import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';

/// Drawable geometry of the loaded dataset, built once per dataset from the
/// public metro_core API. Offline and deterministic. Reading it can throw
/// (a broken dataset): the map screen turns that into "map unavailable".
final mapGeometryProvider = Provider<MapGeometry>((ref) {
  final services = ref.watch(metroServicesProvider);
  return MapGeometry.fromSnapshot(services.snapshot);
});
