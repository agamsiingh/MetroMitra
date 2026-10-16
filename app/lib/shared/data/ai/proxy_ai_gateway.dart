import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:metro_core/metro_core.dart' hide Platform;

/// Talks to MetroMitra's own AI proxy (docs/ai.md). The app holds no vendor
/// key and never contacts a model vendor. Only the question text, locale,
/// dataset-derived facts and an anonymous per-run token are sent: never a
/// position, name or device id.
class ProxyAiGateway implements AiGateway {
  ProxyAiGateway({
    required this.endpoint,
    required this.postCheck,
    this.timeout = const Duration(seconds: 12),
    this.allowInsecureLoopback = false,
    String? token,
  }) : token = token ?? _randomToken();

  /// Full address of `/v1/ask`.
  final Uri endpoint;
  final AiPostCheck postCheck;
  final Duration timeout;

  /// Tests use a loopback server over http; everything else must be https.
  final bool allowInsecureLoopback;

  /// Anonymous, random, kept in memory only (a new one each app start).
  final String token;

  static const maxQuestion = 500;
  static const maxResponseBytes = 16 * 1024;

  @override
  bool get configured => true;

  static String _randomToken() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  bool get _allowed =>
      endpoint.scheme == 'https' ||
      (allowInsecureLoopback &&
          endpoint.scheme == 'http' &&
          (endpoint.host == '127.0.0.1' || endpoint.host == 'localhost'));

  @override
  Future<AiResult> ask(AiRequest request) async {
    if (!_allowed) return const AiUnavailable('address is not https');
    final question = request.question.length > maxQuestion
        ? request.question.substring(0, maxQuestion)
        : request.question;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(endpoint).timeout(timeout);
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      req.add(
        utf8.encode(
          jsonEncode({
            'question': question,
            'locale': request.locale,
            'dataset_version': request.datasetVersion,
            'token': token,
            'grounding': [for (final f in request.grounding) f.toJson()],
          }),
        ),
      );
      final res = await req.close().timeout(timeout);
      final bytes = <int>[];
      await for (final c in res.timeout(timeout)) {
        bytes.addAll(c);
        if (bytes.length > maxResponseBytes) {
          return const AiRefused('response too large');
        }
      }
      if (res.statusCode == HttpStatus.tooManyRequests) {
        return const AiUnavailable('rate limited');
      }
      if (res.statusCode != HttpStatus.ok) {
        return AiUnavailable('service status ${res.statusCode}');
      }
      final Object? j;
      try {
        j = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        return const AiRefused('unreadable response');
      }
      if (j is! Map || j['status'] != 'ok' || j['text'] is! String) {
        return const AiRefused('unexpected response');
      }
      final shown = postCheck.verify(
        j['text'] as String,
        grounding: request.grounding,
      );
      return shown == null
          ? const AiRefused('failed the on-device check')
          : AiAnswer(shown);
    } on TimeoutException {
      return const AiUnavailable('timed out');
    } on SocketException {
      return const AiUnavailable('no network');
    } on HandshakeException {
      return const AiUnavailable('secure connection failed');
    } on HttpException {
      return const AiUnavailable('connection broke');
    } on Object {
      return const AiUnavailable('failed');
    } finally {
      client.close(force: true);
    }
  }
}
