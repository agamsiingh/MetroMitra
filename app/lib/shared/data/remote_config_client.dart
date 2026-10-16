import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Reads the two published tables of the admin backend (Supabase REST) with
/// the public (publishable) key: `ui_config` and `ui_strings`. Row-level
/// security lets the public read these two tables and nothing else.
///
/// HTTPS only, short timeouts, bounded response size. Any failure returns
/// null: the app keeps its last good settings.
class RemoteConfigClient {
  RemoteConfigClient({
    required this.baseUrl,
    required this.publicKey,
    this.timeout = const Duration(seconds: 6),
    this.allowInsecureLoopback = false,
  });

  /// Project address, e.g. `https://xyz.supabase.co`.
  final Uri baseUrl;

  /// The publishable key: a public identifier, never a secret key.
  final String publicKey;
  final Duration timeout;
  final bool allowInsecureLoopback;

  static const maxBytes = 64 * 1024;

  bool get _allowed =>
      baseUrl.scheme == 'https' ||
      (allowInsecureLoopback &&
          baseUrl.scheme == 'http' &&
          (baseUrl.host == '127.0.0.1' || baseUrl.host == 'localhost'));

  /// `(configRows, stringRows)` or null when either read failed.
  Future<(Object?, Object?)?> fetch() async {
    // a secret key must never be shipped or used here
    if (!_allowed ||
        publicKey.isEmpty ||
        publicKey.startsWith('sb_secret_') ||
        publicKey.contains('service_role')) {
      return null;
    }
    final cfg = await _get('ui_config', 'key,value');
    final str = await _get('ui_strings', 'key,lang,text');
    if (cfg == null || str == null) return null;
    return (cfg, str);
  }

  Future<Object?> _get(String table, String select) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = baseUrl.replace(
        path: '/rest/v1/$table',
        queryParameters: {'select': select},
      );
      final req = await client.getUrl(uri).timeout(timeout);
      req.followRedirects = false;
      req.headers
        ..set('apikey', publicKey)
        ..set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }
      final bytes = <int>[];
      await for (final c in res.timeout(timeout)) {
        bytes.addAll(c);
        if (bytes.length > maxBytes) return null;
      }
      return jsonDecode(utf8.decode(bytes));
    } on Object {
      return null; // offline, timeout, bad JSON...
    } finally {
      client.close(force: true);
    }
  }
}
