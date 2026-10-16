import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/shared/data/ai/proxy_ai_gateway.dart';

/// Base address of MetroMitra's AI proxy (`--dart-define=METROMITRA_AI_URL`).
/// A public address, never a key. Empty = no online AI in this build.
const _aiUrl = String.fromEnvironment('METROMITRA_AI_URL');

/// The user's choice to use online AI for questions the dataset cannot answer
/// (docs/ai.md: opt-in setting; default on). The Settings screen (M12) will
/// persist it; until then it lives for the app run.
class OnlineAiEnabled extends Notifier<bool> {
  @override
  bool build() => true;

  // Notifier state is replaced as a whole; a setter keeps call sites short.
  // ignore: use_setters_to_change_properties
  void set({required bool enabled}) => state = enabled;
}

final onlineAiEnabledProvider = NotifierProvider<OnlineAiEnabled, bool>(
  OnlineAiEnabled.new,
);

/// Proxy gateway when the build has an address, else the always-unavailable
/// one. Overridden in tests.
final aiGatewayProvider = Provider<AiGateway>((ref) {
  if (_aiUrl.isEmpty) return const OfflineAiGateway();
  final base = Uri.tryParse(_aiUrl);
  if (base == null) return const OfflineAiGateway();
  final services = ref.watch(metroServicesProvider);
  return ProxyAiGateway(
    endpoint: base.resolve('/v1/ask'),
    postCheck: AiPostCheck(services.snapshot, services.search),
  );
});
