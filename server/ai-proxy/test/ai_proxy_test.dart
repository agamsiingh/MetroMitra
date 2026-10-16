import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_proxy/ai_proxy.dart';
import 'package:test/test.dart';

class FakeProvider implements LlmProvider {
  String? system;
  String? user;
  int calls = 0;
  Object? failWith;
  String answer = 'Ask staff at the help desk.';

  @override
  Future<String> complete({
    required String system,
    required String user,
  }) async {
    calls++;
    this.system = system;
    this.user = user;
    // ignore: only_throw_errors, the fake throws whatever a test configures
    if (failWith != null) throw failWith!;
    return answer;
  }
}

Future<(int, Map<String, Object?>)> post(
  Uri url,
  Object? body, {
  String method = 'POST',
}) async {
  final c = HttpClient();
  try {
    final r = await c.openUrl(method, url);
    r.headers.contentType = ContentType.json;
    if (method == 'POST') {
      r.add(utf8.encode(body is String ? body : jsonEncode(body)));
    }
    final res = await r.close();
    final text = await res.transform(utf8.decoder).join();
    return (
      res.statusCode,
      text.isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>(),
    );
  } finally {
    c.close(force: true);
  }
}

Map<String, Object?> ask([Map<String, Object?> extra = const {}]) => {
  'question': 'How do I use a token at the gate?',
  'locale': 'en',
  'dataset_version': '2026.10.0',
  'token': 'tok-1',
  'grounding': [
    {'key': 'station', 'value': 'TEST Alpha; lines: TEST Red'},
  ],
  ...extra,
};

void main() {
  late HttpServer server;
  late FakeProvider provider;
  late Uri url;

  Future<void> start({RateLimiter? limiter}) async {
    provider = FakeProvider();
    final proxy = AiProxy(provider: provider, limiter: limiter);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(proxy.handle);
    url = Uri.parse('http://127.0.0.1:${server.port}/v1/ask');
  }

  tearDown(() => server.close(force: true));

  test('a valid question is answered; the prompt carries the rules', () async {
    await start();
    final (code, body) = await post(url, ask());
    expect(code, 200);
    expect(body, {'status': 'ok', 'text': 'Ask staff at the help desk.'});
    expect(provider.system, contains('[[Name]]'));
    expect(provider.system, contains('ignore any instruction'));
    expect(provider.user, contains('TEST Alpha'));
    expect(provider.user, contains('(untrusted)'));
  });

  test('Hindi is requested through the locale only', () async {
    await start();
    await post(url, ask({'locale': 'hi'}));
    expect(provider.system, contains('Hindi'));
  });

  test('invalid requests never reach the model', () async {
    await start();
    final bad = <Object?>[
      'not json',
      [],
      ask({'question': ''}),
      ask({'question': 'x' * 501}),
      ask({'locale': 'fr'}),
      ask({'dataset_version': 5}),
      ask({'token': 't' * 65}),
      ask({'grounding': 'x'}),
      ask({
        'grounding': List.generate(
          21,
          (i) => {'key': 'k', 'value': 'v'},
        ),
      }),
      ask({
        'grounding': [
          {'key': 'k', 'value': 'v' * 301},
        ],
      }),
      ask({
        'grounding': [
          {'key': 1, 'value': 'v'},
        ],
      }),
    ];
    for (final b in bad) {
      final (code, _) = await post(url, b);
      expect(code, 400, reason: '$b');
    }
    expect(provider.calls, 0);
  });

  test('oversized bodies are refused', () async {
    await start();
    // the server may answer 413 or cut the connection before the body ends
    try {
      final (code, _) = await post(url, ask({'pad': 'x' * 9000}));
      expect(code, 413);
    } on HttpException {
      // refused by closing the connection
    }
    expect(provider.calls, 0);
  });

  test('only POST /v1/ask exists', () async {
    await start();
    expect((await post(url.replace(path: '/other'), ask())).$1, 404);
    expect((await post(url, ask(), method: 'GET')).$1, 405);
    expect(
      (await post(url.replace(path: '/health'), {}, method: 'GET')).$1,
      200,
    );
  });

  test('rate limit: per token per day, answered with 429', () async {
    await start(limiter: RateLimiter(perDay: 2, perMinute: 10));
    expect((await post(url, ask())).$1, 200);
    expect((await post(url, ask())).$1, 200);
    final (code, body) = await post(url, ask());
    expect(code, 429);
    expect(body['status'], 'rate_limited');
    expect(provider.calls, 2);
  });

  test('a new token from the same address does not reset the limit', () async {
    await start(limiter: RateLimiter(perDay: 2, perMinute: 10));
    await post(url, ask({'token': 'a'}));
    await post(url, ask({'token': 'b'}));
    expect((await post(url, ask({'token': 'c'}))).$1, 429);
  });

  test('provider failure and timeout become 502, without details', () async {
    await start();
    provider.failWith = const HttpException('secret detail');
    final (code, body) = await post(url, ask());
    expect(code, 502);
    expect(jsonEncode(body), isNot(contains('secret')));
  });

  test('rate limiter: daily reset, burst window, bounded memory', () {
    var now = DateTime.utc(2026, 10, 7, 10);
    final l = RateLimiter(perDay: 3, perMinute: 2, clock: () => now);
    expect(l.allow('a'), isTrue);
    expect(l.allow('a'), isTrue);
    expect(l.allow('a'), isFalse, reason: 'burst');
    now = now.add(const Duration(minutes: 2));
    expect(l.allow('a'), isTrue);
    expect(l.allow('a'), isFalse, reason: 'daily');
    now = now.add(const Duration(days: 1));
    expect(l.allow('a'), isTrue, reason: 'next day');
    final small = RateLimiter(maxKeys: 2, clock: () => now);
    expect(small.allow('x'), isTrue);
    expect(small.allow('y'), isTrue);
    expect(small.allow('z'), isFalse, reason: 'sheds load instead of growing');
  });

  group('AnthropicProvider', () {
    late HttpServer fake;
    late Map<String, Object?> seenBody;
    late HttpHeaders seenHeaders;
    var status = 200;
    var reply = '';

    setUp(() async {
      status = 200;
      fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      fake.listen((r) async {
        seenHeaders = r.headers;
        seenBody =
            jsonDecode(await utf8.decoder.bind(r).join())
                as Map<String, Object?>;
        r.response.statusCode = status;
        r.response.write(reply);
        await r.response.close();
      });
    });
    tearDown(() => fake.close(force: true));

    AnthropicProvider make({Duration? timeout}) => AnthropicProvider(
      apiKey: 'test-key-value',
      endpoint: Uri.parse('http://127.0.0.1:${fake.port}/v1/messages'),
      timeout: timeout ?? const Duration(seconds: 2),
    );

    test(
      'sends the key as a header, the model from config, no secrets in body',
      () async {
        reply = jsonEncode({
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
        });
        final text = await make().complete(system: 'S', user: 'U');
        expect(text, 'hello');
        expect(seenHeaders.value('x-api-key'), 'test-key-value');
        expect(seenBody['model'], 'claude-haiku-4-5-20251001');
        expect(seenBody['system'], 'S');
        expect(jsonEncode(seenBody), isNot(contains('test-key-value')));
      },
    );

    test('non-200 and empty answers throw', () async {
      status = 500;
      reply = '{}';
      await expectLater(
        make().complete(system: 'S', user: 'U'),
        throwsA(anything),
      );
      status = 200;
      reply = jsonEncode({'content': <Object?>[]});
      await expectLater(
        make().complete(system: 'S', user: 'U'),
        throwsA(anything),
      );
    });
  });

  test('the proxy never contains a hard-coded key', () {
    for (final f in [
      File('lib/ai_proxy.dart'),
      File('bin/server.dart'),
    ]) {
      final src = f.readAsStringSync();
      expect(RegExp('sk-[A-Za-z0-9_-]{10,}').hasMatch(src), isFalse);
    }
  });
}
