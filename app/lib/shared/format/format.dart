import 'package:flutter/painting.dart';
import 'package:metro_core/metro_core.dart' hide Platform;

/// Display helpers shared by screens. No metro data lives here.

/// `#RRGGBB` (dataset line colours) -> [Color]. A malformed value falls back
/// to [fallback] so a bad colour can never crash a screen.
Color colorFromHex(String hex, {Color fallback = const Color(0xFF607D8B)}) {
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// Names shown for a station in the UI language. The other script is the
/// subtitle when the dataset has it; a missing Hindi name is simply absent
/// (never replaced by a transliteration or a placeholder).
({String primary, String? secondary}) stationTitles({
  required String nameEn,
  required String? nameHi,
  required Locale locale,
}) {
  if (locale.languageCode == 'hi' && nameHi != null) {
    return (primary: nameHi, secondary: nameEn);
  }
  return (primary: nameEn, secondary: nameHi);
}

({String primary, String? secondary}) lineTitles({
  required String nameEn,
  required String? nameHi,
  required Locale locale,
}) => stationTitles(nameEn: nameEn, nameHi: nameHi, locale: locale);

/// Integer paise -> `43` or `43.50` (no floating point).
String formatPaise(int paise) {
  final rupees = paise ~/ 100;
  final rest = paise % 100;
  return rest == 0 ? '$rupees' : '$rupees.${rest.toString().padLeft(2, '0')}';
}

String currencySymbol(String? currency) => switch (currency) {
  'INR' => '₹',
  null => '',
  final c => '$c ',
};

/// Whole minutes for display, never below 1 for a non-zero duration.
int minutesOf(int seconds) {
  if (seconds <= 0) return 0;
  final m = (seconds / 60).round();
  return m < 1 ? 1 : m;
}

/// Day type for a fare quote from the device date. Public holidays are not in
/// the dataset, so only Sundays are recognised (the UI says so).
DayType dayTypeOf(DateTime now) =>
    now.weekday == DateTime.sunday ? DayType.sundayHoliday : DayType.regular;
