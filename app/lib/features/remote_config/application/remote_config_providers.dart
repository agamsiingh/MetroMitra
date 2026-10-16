import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metromitra/features/remote_config/application/remote_config.dart';
import 'package:metromitra/shared/data/remote_config_client.dart';
import 'package:path_provider/path_provider.dart';

/// Admin backend address and its PUBLIC (publishable) key, set at build time
/// (`--dart-define=METROMITRA_SUPABASE_URL=...`). Empty = no remote settings:
/// the app uses its built-in ones. Never a secret / service-role key.
const _url = String.fromEnvironment('METROMITRA_SUPABASE_URL');
const _key = String.fromEnvironment('METROMITRA_SUPABASE_KEY');

final remoteConfigClientProvider = Provider<RemoteConfigClient?>((ref) {
  final base = Uri.tryParse(_url);
  if (_url.isEmpty || _key.isEmpty || base == null) return null;
  return RemoteConfigClient(baseUrl: base, publicKey: _key);
});

/// Where the last good settings are kept (validated values only), or null
/// where there is no app storage.
final remoteConfigFileProvider = FutureProvider<File?>((ref) async {
  try {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/remote_config.json');
  } on Object {
    return null;
  }
});

/// The settings in force. Starts with the last good ones (or the built-in
/// defaults) so the first frame never waits for the network; a successful
/// fetch replaces them and is saved. Failure keeps what is there.
class RemoteConfigNotifier extends Notifier<RemoteConfig> {
  @override
  RemoteConfig build() {
    unawaited(_load());
    return RemoteConfig.defaults;
  }

  Future<void> _load() async {
    final file = await ref.read(remoteConfigFileProvider.future);
    try {
      if (file != null && file.existsSync()) {
        final saved = RemoteConfig.fromJson(
          jsonDecode(file.readAsStringSync()),
        );
        if (ref.mounted) state = saved;
      }
    } on Object {
      // unreadable cache: defaults stay
    }
    await refresh();
  }

  /// One fetch from the admin backend; keeps the current settings on failure.
  Future<void> refresh() async {
    final client = ref.read(remoteConfigClientProvider);
    if (client == null) return;
    final rows = await client.fetch();
    if (rows == null || !ref.mounted) return;
    final fresh = RemoteConfig.fromRows(
      configRows: rows.$1,
      stringRows: rows.$2,
    );
    state = fresh;
    try {
      final file = await ref.read(remoteConfigFileProvider.future);
      file?.writeAsStringSync(jsonEncode(fresh.toJson()), flush: true);
    } on Object {
      // not saved: still applied for this run
    }
  }
}

final remoteConfigProvider =
    NotifierProvider<RemoteConfigNotifier, RemoteConfig>(
      RemoteConfigNotifier.new,
    );

/// The admin's replacement for [key] in the current language, or [fallback]
/// (the built-in text from the ARB files).
String remoteText(
  WidgetRef ref,
  BuildContext context,
  String key,
  String fallback,
) {
  final lang = Localizations.localeOf(context).languageCode == 'hi'
      ? 'hi'
      : 'en';
  return ref.watch(remoteConfigProvider).text(key, lang) ?? fallback;
}
