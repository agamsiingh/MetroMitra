import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/shared/data/ai/proxy_ai_gateway.dart';

import 'support/test_network.dart';

/// Plain `test()`s only: a widget test in the same file would install
/// flutter_test's fake HttpClient and block the loopback server.
void main() {
  group('ProxyAiGateway against a local server', () {
    late HttpServer server;
    late Map<String, Object?> seen;
    var status = 200;
    var reply = '';
    var hang = false;
    late AiPostCheck check;
    late ProxyAiGateway gw;

    const req = AiRequest(
      question: 'How do I use a token?',
      locale: 'en',
      grounding: [AiFact('station', 'Alpha Chowk; lines: Test Red Line')],
      datasetVersion: '2026.10.0',
    );

    setUp(() async {
      status = 200;
      hang = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        seen = (jsonDecode(await utf8.decoder.bind(r).join()) as Map)
            .cast<String, Object?>();
        if (hang) return;
        r.response.statusCode = status;
        r.response.write(reply);
        await r.response.close();
      });
      final services = MetroServices(demoNetwork());
      check = AiPostCheck(services.snapshot, services.search);
      gw = ProxyAiGateway(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/ask'),
        postCheck: check,
        allowInsecureLoopback: true,
        timeout: const Duration(milliseconds: 600),
      );
    });
    tearDown(() => server.close(force: true));

    test('sends only question, locale, facts, dataset version and a random '
        'token', () async {
      reply = jsonEncode({'status': 'ok', 'text': 'Tap in, tap out.'});
      final r = await gw.ask(req);
      expect(r, isA<AiAnswer>());
      expect(seen.keys.toSet(), {
        'question',
        'locale',
        'dataset_version',
        'token',
        'grounding',
      });
      expect((seen['token']! as String).length, 32);
      expect(jsonEncode(seen), isNot(contains('lat')));
    });

    test('markers are removed and a made-up station is refused', () async {
      reply = jsonEncode({
        'status': 'ok',
        'text': 'Change at [[Alpha Chowk]].',
      });
      expect((await gw.ask(req) as AiAnswer).text, 'Change at Alpha Chowk.');
      reply = jsonEncode({'status': 'ok', 'text': 'Change at [[Narnia]].'});
      expect(await gw.ask(req), isA<AiRefused>());
    });

    test('invented fares and times are refused', () async {
      reply = jsonEncode({'status': 'ok', 'text': 'It costs ₹60.'});
      expect(await gw.ask(req), isA<AiRefused>());
      reply = jsonEncode({'status': 'ok', 'text': 'Last train 23:45.'});
      expect(await gw.ask(req), isA<AiRefused>());
    });

    test('429, 5xx, garbage and wrong shape', () async {
      status = 429;
      reply = '{}';
      expect((await gw.ask(req) as AiUnavailable).reason, 'rate limited');
      status = 502;
      expect(await gw.ask(req), isA<AiUnavailable>());
      status = 200;
      reply = 'nope';
      expect(await gw.ask(req), isA<AiRefused>());
      reply = jsonEncode({'status': 'ok', 'text': 5});
      expect(await gw.ask(req), isA<AiRefused>());
      reply = jsonEncode({'status': 'ok', 'text': 'x' * 20000});
      expect(await gw.ask(req), isA<AiRefused>());
    });

    test(
      'timeout and no network are unavailable, never an exception',
      () async {
        hang = true;
        expect((await gw.ask(req) as AiUnavailable).reason, 'timed out');
        final port = server.port;
        await server.close(force: true);
        final dead = ProxyAiGateway(
          endpoint: Uri.parse('http://127.0.0.1:$port/v1/ask'),
          postCheck: check,
          allowInsecureLoopback: true,
        );
        expect(await dead.ask(req), isA<AiUnavailable>());
      },
    );

    test(
      'plain http is refused outside tests; long questions are cut',
      () async {
        final strict = ProxyAiGateway(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/ask'),
          postCheck: check,
        );
        expect(await strict.ask(req), isA<AiUnavailable>());
        reply = jsonEncode({'status': 'ok', 'text': 'fine'});
        await gw.ask(
          AiRequest(
            question: 'q' * 900,
            locale: 'en',
            grounding: const [],
            datasetVersion: 'v',
          ),
        );
        expect((seen['question']! as String).length, 500);
      },
    );
  });
}
