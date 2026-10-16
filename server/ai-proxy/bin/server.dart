import 'dart:io';

import 'package:ai_proxy/ai_proxy.dart';

/// Runs the proxy. Configuration is environment only:
/// `AI_API_KEY` (required, never printed), `AI_MODEL`, `AI_PORT`,
/// `AI_PER_DAY`. Put it behind TLS (Cloudflare, a load balancer): the app
/// refuses plain http.
Future<void> main() async {
  final env = Platform.environment;
  final key = env['AI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('AI_API_KEY is not set; refusing to start.');
    exit(64);
  }
  final proxy = AiProxy(
    provider: AnthropicProvider(
      apiKey: key,
      model: env['AI_MODEL'] ?? 'claude-haiku-4-5-20251001',
    ),
    limiter: RateLimiter(perDay: int.tryParse(env['AI_PER_DAY'] ?? '') ?? 20),
  );
  final port = int.tryParse(env['AI_PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('ai-proxy listening on $port');
  // handle() never throws; requests are served concurrently
  await server.forEach(proxy.handle);
}
