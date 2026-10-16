import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/dart.dart';

/// Lower-case hex sha256 of [bytes].
String sha256Hex(List<int> bytes) {
  final digest = const DartSha256().hashSync(bytes).bytes;
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Deterministic JSON: object keys sorted recursively, 2-space indent, one
/// trailing newline. The same value always yields the same bytes.
String canonicalJson(Object? value, {bool pretty = true}) {
  final text = pretty
      ? const JsonEncoder.withIndent('  ').convert(_sorted(value))
      : jsonEncode(_sorted(value));
  return pretty ? '$text\n' : text;
}

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is Iterable) return [for (final x in v) _sorted(x)];
  return v;
}

/// Great-circle distance in metres.
double haversineM(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
}

/// Lower-case ASCII slug (`Rajiv Chowk` -> `rajiv-chowk`); empty if the text
/// has no ASCII letters or digits.
String slug(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Comparison key: lower-case letters and digits of any script only.
String nameKey(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Trim and collapse internal whitespace; nothing else is changed.
String tidy(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Rounds a coordinate to 6 decimals (about 0.1 m) for stable output.
double round6(double v) => (v * 1e6).roundToDouble() / 1e6;
