import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/go/application/route_lookup.dart';
import 'package:metromitra/features/journey/application/journey_controller.dart';
import 'package:metromitra/shared/data/updater/dataset_updater.dart';
import 'package:metromitra/shared/data/updater/update_transport.dart';

/// Where the signed manifest is published (`--dart-define=METROMITRA_UPDATE_URL`).
/// Empty = no updates: the app stays fully offline.
const _updateUrl = String.fromEnvironment('METROMITRA_UPDATE_URL');

/// Version of this app build (kept equal to pubspec.yaml by a test).
const appVersion = '0.1.0';

/// Public Ed25519 keys (base64) trusted to sign datasets: the current one and
/// the next one (docs/sync.md). Public keys only; the private key lives in CI
/// secrets. **Empty until the owner generates the production key**: with no
/// key no update can ever verify, so nothing is installed.
const trustedPublicKeys = <String>[];

final updaterProvider = FutureProvider<DatasetUpdater?>((ref) async {
  final store = await ref.watch(datasetStoreProvider.future);
  if (store == null) return null;
  return DatasetUpdater(
    store: store,
    transport: HttpUpdateTransport(),
    verifier: ManifestVerifier([
      for (final k in trustedPublicKeys) TrustedKey.fromBase64(k),
    ]),
    appVersion: appVersion,
    manifestUrl: _updateUrl.isEmpty ? null : Uri.tryParse(_updateUrl),
    policy: ref.watch(datasetPolicyProvider),
  );
});

/// The once-a-day background check, started after the first frame. Result is
/// informational; the new dataset is used from the next launch, so a running
/// journey or route is never changed under the user.
final updateCheckProvider = FutureProvider<UpdateResult?>((ref) async {
  if (kDebugMode && _updateUrl.isEmpty) return null;
  final updater = await ref.watch(updaterProvider.future);
  if (updater == null || !updater.enabled) return null;
  final store = updater.store;
  final now = ref.read(clockProvider)();
  if (!updateIsDue(store.lastCheck, now)) return null;
  if (ref.read(activeJourneyProvider) is! NoJourney) {
    return null; // not mid-journey
  }
  store.recordCheck(now);
  return updater.run();
});
