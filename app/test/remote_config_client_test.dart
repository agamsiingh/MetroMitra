import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metromitra/features/remote_config/application/remote_config.dart';
import 'package:metromitra/shared/data/remote_config_client.dart';

/// Plain `test()`s only (a widget test in the same file would install a fake
/// HttpClient and block the loopback server).
void main() {
  late HttpServer server;
  late List<String> paths;
  late List<String> keys;
  var config = '[]';
  var strings = '[]';
  var configStatus = 200;
  var hang = false;

  setUp(() async {
    paths = [];
    keys = [];
    config = '[]';
    strings = '[]';
    configStatus = 200;
    hang = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      paths.add(r.uri.toString());
      keys.add(r.headers.value('apikey') ?? '');
      if (hang) return;
      final isConfig = r.uri.path.endsWith('/ui_config');
      r.response.statusCode = isConfig ? configStatus : 200;
      r.response.write(isConfig ? config : strings);
      await r.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  RemoteConfigClient client({
    String key = 'sb_publishable_test',
    bool loopback = true,
  }) => RemoteConfigClient(
    baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    publicKey: key,
    timeout: const Duration(milliseconds: 600),
    allowInsecureLoopback: loopback,
  );

  test('reads both published tables with only the public key', () async {
    config = jsonEncode([
      {
        'key': 'flags',
        'value': {'online_ai': false},
      },
    ]);
    strings = jsonEncode([
      {'key': 'homeHeading', 'lang': 'en', 'text': 'Hello'},
    ]);
    final rows = await client().fetch();
    expect(rows, isNotNull);
    final cfg = RemoteConfig.fromRows(
      configRows: rows!.$1,
      stringRows: rows.$2,
    );
    expect(cfg.flags.onlineAi, isFalse);
    expect(cfg.text('homeHeading', 'en'), 'Hello');
    expect(paths, [
      '/rest/v1/ui_config?select=key%2Cvalue',
      '/rest/v1/ui_strings?select=key%2Clang%2Ctext',
    ]);
    expect(keys.toSet(), {'sb_publishable_test'});
  });

  test('failure of either read keeps the old settings (null)', () async {
    configStatus = 401;
    expect(await client().fetch(), isNull);
    configStatus = 200;
    config = 'not json';
    expect(await client().fetch(), isNull);
  });

  test('timeout and no server give null, never an exception', () async {
    hang = true;
    expect(await client().fetch(), isNull);
    final port = server.port;
    await server.close(force: true);
    final dead = RemoteConfigClient(
      baseUrl: Uri.parse('http://127.0.0.1:$port'),
      publicKey: 'k',
      timeout: const Duration(milliseconds: 500),
      allowInsecureLoopback: true,
    );
    expect(await dead.fetch(), isNull);
  });

  test(
    'plain http is refused outside tests; secret keys are refused',
    () async {
      expect(await client(loopback: false).fetch(), isNull);
      expect(paths, isEmpty);
      expect(await client(key: 'sb_secret_abc').fetch(), isNull);
      expect(await client(key: 'eyJ.service_role.x').fetch(), isNull);
      expect(await client(key: '').fetch(), isNull);
      expect(paths, isEmpty);
    },
  );

  test('an oversized answer is dropped', () async {
    config = jsonEncode([
      {
        'key': 'x',
        'value': {'pad': 'a' * (RemoteConfigClient.maxBytes + 10)},
      },
    ]);
    expect(await client().fetch(), isNull);
  });

  group('parsing', () {
    RemoteConfig parse(Object? c, [Object? s = const <Object>[]]) =>
        RemoteConfig.fromRows(configRows: c, stringRows: s);

    test('garbage anywhere falls back to the defaults', () {
      for (final bad in <Object?>[
        null,
        'x',
        5,
        <Object>[],
        {'a': 1},
      ]) {
        expect(parse(bad, bad), RemoteConfig.defaults);
      }
      expect(
        parse([
          {'key': 'flags', 'value': 'nope'},
          <String, Object?>{'key': 5, 'value': <String, Object?>{}},
          'row',
        ]),
        RemoteConfig.defaults,
      );
    });

    test('flags: only real booleans count', () {
      final c = parse([
        {
          'key': 'flags',
          'value': {
            'online_ai': 'false',
            'show_dmrc_map': false,
            'show_overview_map': 0,
          },
        },
      ]);
      expect(c.flags.onlineAi, isTrue, reason: 'a string is not a boolean');
      expect(c.flags.showDmrcMap, isFalse);
      expect(c.flags.showOverviewMap, isTrue);
    });

    test('announcement: needs enabled + English text, length capped', () {
      Announcement a(Map<String, Object?> v) => parse([
        {'key': 'announcement', 'value': v},
      ]).announcement;
      expect(
        a({
          'enabled': true,
          'text_en': 'Service change',
          'text_hi': 'बदलाव',
          'severity': 'warning',
        }).textFor('hi'),
        'बदलाव',
      );
      expect(
        a({'enabled': true, 'text_en': 'Only English'}).textFor('hi'),
        'Only English',
        reason: 'falls back to English',
      );
      expect(a({'enabled': false, 'text_en': 'x'}).textFor('en'), isNull);
      expect(a({'enabled': true, 'text_en': ''}).textFor('en'), isNull);
      expect(
        a({'enabled': true, 'text_en': 'x' * 281}).textFor('en'),
        isNull,
      );
      expect(a({'enabled': 'true', 'text_en': 'x'}).textFor('en'), isNull);
    });

    test('texts: only the allowed keys, languages and lengths', () {
      final c = parse(
        const <Object>[],
        [
          {'key': 'homeHeading', 'lang': 'hi', 'text': ' नमस्ते '},
          {'key': 'fareTable', 'lang': 'en', 'text': 'Fare is 5'},
          {'key': 'askIntro', 'lang': 'fr', 'text': 'x'},
          {'key': 'askIntro', 'lang': 'en', 'text': 'x' * 501},
          {'key': 'askIntro', 'lang': 'en', 'text': '   '},
        ],
      );
      expect(c.texts, {'homeHeading/hi': 'नमस्ते'});
    });

    test('colour: #RRGGBB only', () {
      Object? row(Object? v) => [
        {
          'key': 'theme',
          'value': {'seed_color': v},
        },
      ];
      expect(parse(row('#0B3D91')).seedColor, isNotNull);
      for (final bad in ['0B3D91', 'red', '#12', '#GGGGGG', 5, null]) {
        expect(parse(row(bad)).seedColor, isNull, reason: '$bad');
      }
    });

    test('what is saved reads back the same, and a tampered file is safe', () {
      final c = parse(
        [
          {
            'key': 'flags',
            'value': {'show_map_search': false},
          },
          {
            'key': 'theme',
            'value': {'seed_color': '#0B3D91'},
          },
        ],
        [
          {'key': 'homeHeading', 'lang': 'en', 'text': 'Hi'},
        ],
      );
      expect(RemoteConfig.fromJson(jsonDecode(jsonEncode(c.toJson()))), c);
      expect(RemoteConfig.fromJson('junk'), RemoteConfig.defaults);
      final evil = {
        'texts': {'fareTable/en': 'Fare is 5', 'homeHeading/en': 'ok'},
        'flags': {'online_ai': 'no'},
      };
      final r = RemoteConfig.fromJson(evil);
      expect(r.texts, {'homeHeading/en': 'ok'});
      expect(r.flags.onlineAi, isTrue);
    });
  });

  test('the client and parser contain no key and no storage of secrets', () {
    for (final f in [
      File('lib/shared/data/remote_config_client.dart'),
      File('lib/features/remote_config/application/remote_config.dart'),
      File(
        'lib/features/remote_config/application/remote_config_providers.dart',
      ),
    ]) {
      final src = f.readAsStringSync();
      expect(RegExp('sb_publishable_[A-Za-z0-9_]{10,}').hasMatch(src), isFalse);
      expect(RegExp('eyJ[A-Za-z0-9_-]{20,}').hasMatch(src), isFalse);
    }
  });
}
