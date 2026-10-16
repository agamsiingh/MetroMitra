import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app consumes metro_core only through its public library, and metro_core
/// stays UI-free (the latter is also enforced by tools/check.dart).
void main() {
  final files = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.dart') &&
          !f.path.contains('generated'))
        f,
  ];

  test('there are app sources to check', () {
    expect(files, isNotEmpty);
  });

  test('app code never imports metro_core internals', () {
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(
        src.contains('package:metro_core/src/'),
        isFalse,
        reason: '${f.path} reaches into metro_core/src',
      );
    }
  });

  test('metro_core imports in the app hide its Platform class', () {
    // metro_core exports a station-facts `Platform` that clashes with dart:io.
    final importRe = RegExp(
      "import 'package:metro_core/metro_core.dart'([^;]*);",
    );
    for (final f in files) {
      for (final m in importRe.allMatches(f.readAsStringSync())) {
        expect(
          m.group(1),
          contains('hide Platform'),
          reason: '${f.path} should import metro_core with "hide Platform"',
        );
      }
    }
  });

  test('no metro data in app code: no station, line or fare literals', () {
    // Names such as these belong to the dataset only.
    final forbidden = RegExp(
      'Rajiv Chowk|Kashmere Gate|Blue Line|Yellow Line|Dwarka|Noida',
      caseSensitive: false,
    );
    for (final f in files) {
      expect(
        forbidden.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${f.path} contains metro data',
      );
    }
  });

  test('no dataset is bundled with the app', () {
    final bundled = Directory('assets/data')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.sqlite') ||
              f.path.endsWith('.db') ||
              f.path.endsWith('.json'),
        );
    expect(bundled, isEmpty, reason: 'the draft dataset must not be bundled');
  });

  test('only shared/location touches the platform location plugin', () {
    for (final f in files) {
      final src = f.readAsStringSync();
      if (src.contains('package:geolocator/')) {
        expect(
          f.path.replaceAll(r'\', '/'),
          contains('lib/shared/location/'),
          reason: '${f.path} must go through LocationSource',
        );
      }
    }
  });

  test('position handling never stores or sends anything', () {
    // Location + Nearby code may not use files, sockets, HTTP, preferences
    // or databases: a position stays in memory (docs/security.md).
    final forbidden = RegExp(
      'dart:io|dart:html|package:http|package:dio|shared_preferences|'
      r'package:drift|package:sqlite3|File\(|Socket|HttpClient|'
      r'print\(|debugPrint|log\(',
    );
    for (final f in files) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.contains('lib/shared/location/') &&
          !p.contains('lib/features/nearby/') &&
          !p.contains('lib/features/map/application/live_tracking')) {
        continue;
      }
      expect(
        forbidden.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '$p stores, logs or sends data',
      );
    }
  });

  test('the map is offline by construction: no network, IO or map plugins', () {
    final forbidden = RegExp(
      'dart:io|dart:html|package:http|package:dio|package:flutter_map|'
      'package:google_maps|package:maplibre|package:mapbox|'
      r'package:latlong|WebView|NetworkImage|Image\.network|Uri\.https?\(',
    );
    var checked = 0;
    for (final f in files) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.contains('lib/features/map/')) continue;
      checked++;
      expect(
        forbidden.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '$p can reach the network',
      );
    }
    expect(checked, greaterThan(0));
  });

  test('pubspec has no map, tile or web-view dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dep in [
      'flutter_map',
      'google_maps_flutter',
      'maplibre',
      'mapbox',
      'latlong2',
      'webview_flutter',
      'http:',
      'dio:',
    ]) {
      expect(pubspec.contains(dep), isFalse, reason: 'pubspec lists $dep');
    }
  });

  test('journey code: no network, no files, no ads; storage only via '
      'JourneyStore', () {
    final forbidden = RegExp(
      'dart:io|dart:html|package:http|package:dio|package:sqlite3|'
      'package:path_provider|google_mobile_ads|BannerAd|NativeAd|'
      r'shared_preferences|print\(|debugPrint',
    );
    var checked = 0;
    for (final f in files) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.contains('lib/features/journey/')) continue;
      checked++;
      expect(forbidden.hasMatch(f.readAsStringSync()), isFalse, reason: p);
    }
    expect(checked, greaterThan(0));
  });

  test('the saved journey never contains a position', () {
    final src = File(
      'lib/features/journey/application/journey_controller.dart',
    ).readAsStringSync();
    final save = src.substring(src.indexOf('jsonEncode({'));
    final body = save.substring(0, save.indexOf('});'));
    expect(body.contains('lat'), isFalse);
    expect(body.contains('lng'), isFalse);
    expect(body.contains('accuracy'), isFalse);
  });

  test('assistant code: offline only, no ads, nothing stored or logged', () {
    final forbidden = RegExp(
      'dart:io|dart:html|package:http|package:dio|package:sqlite3|'
      'package:path_provider|shared_preferences|google_mobile_ads|BannerAd|'
      r'NativeAd|JourneyStore|print\(|debugPrint|LocationSource',
    );
    var checked = 0;
    for (final f in files) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.contains('lib/features/assistant/')) continue;
      checked++;
      expect(forbidden.hasMatch(f.readAsStringSync()), isFalse, reason: p);
    }
    expect(checked, greaterThan(0));
  });

  test('updater: HTTPS-only transport, public keys only, no signing code', () {
    final forbidden = RegExp(
      r'newKeyPairFromSeed|newKeyPair\(|extractPrivateKey|\.sign\(|'
      'METROMITRA_SIGNING_KEY|PRIVATE KEY|package:http|package:dio|'
      r'print\(|debugPrint',
    );
    var checked = 0;
    for (final f in files) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.contains('lib/shared/data/updater/') &&
          !p.contains('lib/bootstrap/update_providers')) {
        continue;
      }
      checked++;
      expect(forbidden.hasMatch(f.readAsStringSync()), isFalse, reason: p);
    }
    expect(checked, greaterThan(2));
  });

  test('only the updater and the bootstrap touch the network', () {
    for (final f in files) {
      final p = f.path.replaceAll(r'\', '/');
      if (p.contains('lib/shared/data/updater/update_transport.dart') ||
          p.contains('lib/shared/data/ai/proxy_ai_gateway.dart') ||
          p.contains('lib/shared/data/remote_config_client.dart')) {
        continue;
      }
      expect(
        RegExp(r'HttpClient|Socket\(|WebSocket').hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '$p opens network connections',
      );
    }
  });
}
