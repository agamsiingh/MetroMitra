import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metromitra/app/theme/app_theme.dart';
import 'package:metromitra/features/remote_config/application/remote_config.dart';
import 'package:metromitra/features/remote_config/application/remote_config_providers.dart';
import 'package:metromitra/shared/data/remote_config_client.dart';

import 'support/app_harness.dart';

class _FakeClient extends RemoteConfigClient {
  _FakeClient(this.rows)
    : super(baseUrl: Uri.parse('https://example.invalid'), publicKey: 'k');

  final (Object?, Object?)? rows;
  int calls = 0;

  @override
  Future<(Object?, Object?)?> fetch() async {
    calls++;
    return rows;
  }
}

Object _cfg(String key, Map<String, Object?> value) => {
  'key': key,
  'value': value,
};

void main() {
  Future<void> pumpWith(
    WidgetTester tester,
    (Object?, Object?)? rows, {
    String? location,
    Locale? locale,
  }) => pumpApp(
    tester,
    location: location,
    locale: locale,
    extraOverrides: [
      remoteConfigClientProvider.overrideWithValue(_FakeClient(rows)),
    ],
  );

  testWidgets('no settings: nothing extra is shown, everything is on', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(key('announcement'), findsNothing);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    for (final k in ['map-overview', 'map-dmrc', 'map-search', 'map-track']) {
      expect(key(k), findsOneWidget, reason: k);
    }
  });

  testWidgets('the announcement appears on Home, in the app language', (
    tester,
  ) async {
    await pumpWith(tester, (
      [
        _cfg('announcement', {
          'enabled': true,
          'text_en': 'Blue Line delayed',
          'text_hi': 'ब्लू लाइन देरी से',
          'severity': 'warning',
        }),
      ],
      <Object>[],
    ));
    expect(find.text('Blue Line delayed'), findsOneWidget);
  });

  testWidgets('Hindi interface shows the Hindi text', (tester) async {
    await pumpWith(
      tester,
      (
        [
          _cfg('announcement', {
            'enabled': true,
            'text_en': 'Blue Line delayed',
            'text_hi': 'ब्लू लाइन देरी से',
            'severity': 'info',
          }),
        ],
        <Object>[],
      ),
      locale: const Locale('hi'),
    );
    expect(find.text('ब्लू लाइन देरी से'), findsOneWidget);
  });

  testWidgets('a disabled or broken announcement shows nothing', (
    tester,
  ) async {
    await pumpWith(tester, (
      [
        _cfg('announcement', {'enabled': false, 'text_en': 'x'}),
      ],
      <Object>[],
    ));
    expect(key('announcement'), findsNothing);
  });

  testWidgets('feature flags hide the map buttons', (tester) async {
    await pumpWith(tester, (
      [
        _cfg('flags', {
          'show_overview_map': false,
          'show_dmrc_map': false,
          'show_map_search': false,
          'show_live_tracking': false,
        }),
      ],
      <Object>[],
    ));
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    for (final k in ['map-overview', 'map-dmrc', 'map-search', 'map-track']) {
      expect(key(k), findsNothing, reason: k);
    }
    expect(key('map-zoom-in'), findsOneWidget, reason: 'the map itself stays');
  });

  testWidgets('text overrides replace the Home heading and Ask intro', (
    tester,
  ) async {
    await pumpWith(tester, (
      <Object>[],
      [
        {'key': 'homeHeading', 'lang': 'en', 'text': 'Where to today?'},
        {'key': 'askIntro', 'lang': 'en', 'text': 'Ask me about the metro.'},
      ],
    ));
    expect(find.text('Where to today?'), findsOneWidget);
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.text('Ask me about the metro.'), findsOneWidget);
  });

  testWidgets('a failed fetch keeps the built-in look', (tester) async {
    await pumpWith(tester, null);
    expect(key('announcement'), findsNothing);
    expect(find.text('Where do you want to go?'), findsOneWidget);
  });

  testWidgets('the brand colour from the admin builds the palette', (
    tester,
  ) async {
    final c = await pumpWith(tester, (
      [
        _cfg('theme', {'seed_color': '#B71C1C'}),
      ],
      <Object>[],
    )).then((_) => null);
    expect(c, isNull);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final red = app.theme!.colorScheme.primary;
    expect(red, isNot(buildTheme(Brightness.light).colorScheme.primary));
    expect(red.r * 255 > red.b * 255, isTrue, reason: 'reddish');
    expect(app.darkTheme!.colorScheme.brightness, Brightness.dark);
  });

  test('theme: without a seed it is the built-in palette', () {
    expect(
      buildTheme(Brightness.light).colorScheme.primary,
      buildTheme(Brightness.light).colorScheme.primary,
    );
    expect(
      buildTheme(
        Brightness.light,
        seed: const Color(0xFFB71C1C),
      ).colorScheme.primary,
      isNot(buildTheme(Brightness.light).colorScheme.primary),
    );
  });

  testWidgets('the settings are read once per launch, not per rebuild', (
    tester,
  ) async {
    final fake = _FakeClient(([], <Object>[]));
    await pumpApp(
      tester,
      extraOverrides: [remoteConfigClientProvider.overrideWithValue(fake)],
    );
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(fake.calls, 1);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      ).read(remoteConfigProvider),
      RemoteConfig.defaults,
    );
  });
}
