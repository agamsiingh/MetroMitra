import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Settings the admin panel may change (docs/admin.md). The app understands
/// only the keys listed here; anything else, or a value of the wrong type or
/// size, is ignored and the built-in default is used. None of this can
/// change a metro fact: stations, fares, gates and timings come from the
/// signed dataset only.
@immutable
class RemoteConfig {
  const RemoteConfig({
    this.announcement = Announcement.none,
    this.flags = Flags.defaults,
    this.seedColor,
    this.texts = const {},
  });

  /// Builds a config from the two published tables. Never throws.
  factory RemoteConfig.fromRows({
    required Object? configRows,
    required Object? stringRows,
  }) {
    final cfg = <String, Map<String, Object?>>{};
    if (configRows is List) {
      for (final r in configRows) {
        if (r is Map && r['key'] is String && r['value'] is Map) {
          cfg[r['key'] as String] = (r['value'] as Map).cast<String, Object?>();
        }
      }
    }
    final texts = <String, String>{};
    if (stringRows is List) {
      for (final r in stringRows) {
        if (r is! Map) continue;
        final key = r['key'];
        final lang = r['lang'];
        final text = r['text'];
        if (key is String &&
            allowedTextKeys.contains(key) &&
            (lang == 'en' || lang == 'hi') &&
            text is String &&
            text.trim().isNotEmpty &&
            text.length <= maxTextLength) {
          texts['$key/$lang'] = text.trim();
        }
      }
    }
    return RemoteConfig(
      announcement: Announcement.parse(cfg['announcement']),
      flags: Flags.parse(cfg['flags']),
      seedColor: _color(cfg['theme']?['seed_color']),
      texts: Map.unmodifiable(texts),
    );
  }

  factory RemoteConfig.fromJson(Object? j) {
    if (j is! Map) return defaults;
    final texts = <String, String>{};
    final t = j['texts'];
    if (t is Map) {
      for (final e in t.entries) {
        final k = e.key;
        if (k is String &&
            e.value is String &&
            allowedTextKeys.contains(k.split('/').first) &&
            (e.value as String).length <= maxTextLength) {
          texts[k] = e.value as String;
        }
      }
    }
    return RemoteConfig(
      announcement: Announcement.parse(j['announcement']),
      flags: Flags.parse(j['flags']),
      seedColor: _color(j['seed']),
      texts: Map.unmodifiable(texts),
    );
  }

  static const defaults = RemoteConfig();

  final Announcement announcement;
  final Flags flags;

  /// Brand colour for the generated palette; null = the built-in colour.
  final Color? seedColor;

  /// Text overrides by `<key>/<lang>` (only [allowedTextKeys]).
  final Map<String, String> texts;

  /// Texts the admin may replace. Deliberately tiny and free of facts.
  static const allowedTextKeys = {'homeHeading', 'askIntro'};

  static const maxTextLength = 500;
  static const maxAnnouncementLength = 280;

  /// The override for [key] in [lang] (`en` or `hi`), or null.
  String? text(String key, String lang) => texts['$key/$lang'];

  /// Persisted form (only validated values), and its inverse.
  Map<String, Object?> toJson() => {
    'announcement': announcement.toJson(),
    'flags': flags.toJson(),
    'seed': seedColor == null ? null : _hex(seedColor!),
    'texts': texts,
  };

  static final _hexRe = RegExp(r'^#[0-9a-fA-F]{6}$');

  static Color? _color(Object? v) {
    if (v is! String || !_hexRe.hasMatch(v)) return null;
    return Color(0xFF000000 | int.parse(v.substring(1), radix: 16));
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  bool operator ==(Object other) =>
      other is RemoteConfig &&
      other.announcement == announcement &&
      other.flags == flags &&
      other.seedColor == seedColor &&
      _sameMap(other.texts, texts);

  @override
  int get hashCode => Object.hash(announcement, flags, seedColor, texts.length);

  static bool _sameMap(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}

enum AnnouncementSeverity { info, warning }

@immutable
class Announcement {
  const Announcement({
    required this.enabled,
    required this.textEn,
    required this.textHi,
    required this.severity,
  });

  factory Announcement.parse(Object? v) {
    if (v is! Map) return none;
    final en = v['text_en'];
    final hi = v['text_hi'];
    if (v['enabled'] != true ||
        en is! String ||
        en.trim().isEmpty ||
        en.length > RemoteConfig.maxAnnouncementLength ||
        (hi != null &&
            (hi is! String ||
                hi.length > RemoteConfig.maxAnnouncementLength))) {
      return none;
    }
    return Announcement(
      enabled: true,
      textEn: en.trim(),
      textHi: hi is String ? hi.trim() : '',
      severity: v['severity'] == 'warning'
          ? AnnouncementSeverity.warning
          : AnnouncementSeverity.info,
    );
  }

  static const none = Announcement(
    enabled: false,
    textEn: '',
    textHi: '',
    severity: AnnouncementSeverity.info,
  );

  final bool enabled;
  final String textEn;
  final String textHi;
  final AnnouncementSeverity severity;

  /// The text to show in [lang], falling back to English; null = no banner.
  String? textFor(String lang) {
    if (!enabled) return null;
    final t = lang == 'hi' && textHi.isNotEmpty ? textHi : textEn;
    return t.isEmpty ? null : t;
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'text_en': textEn,
    'text_hi': textHi,
    'severity': severity.name,
  };

  @override
  bool operator ==(Object other) =>
      other is Announcement &&
      other.enabled == enabled &&
      other.textEn == textEn &&
      other.textHi == textHi &&
      other.severity == severity;

  @override
  int get hashCode => Object.hash(enabled, textEn, textHi, severity);
}

@immutable
class Flags {
  const Flags({
    this.onlineAi = true,
    this.showOverviewMap = true,
    this.showDmrcMap = true,
    this.showLiveTracking = true,
    this.showMapSearch = true,
  });

  /// Each flag falls back to its default unless it is a real boolean.
  factory Flags.parse(Object? v) {
    if (v is! Map) return defaults;
    bool b(String k, {required bool fallback}) =>
        v[k] is bool ? v[k] as bool : fallback;
    return Flags(
      onlineAi: b('online_ai', fallback: true),
      showOverviewMap: b('show_overview_map', fallback: true),
      showDmrcMap: b('show_dmrc_map', fallback: true),
      showLiveTracking: b('show_live_tracking', fallback: true),
      showMapSearch: b('show_map_search', fallback: true),
    );
  }

  static const defaults = Flags();

  final bool onlineAi;
  final bool showOverviewMap;
  final bool showDmrcMap;
  final bool showLiveTracking;
  final bool showMapSearch;

  Map<String, Object?> toJson() => {
    'online_ai': onlineAi,
    'show_overview_map': showOverviewMap,
    'show_dmrc_map': showDmrcMap,
    'show_live_tracking': showLiveTracking,
    'show_map_search': showMapSearch,
  };

  @override
  bool operator ==(Object other) =>
      other is Flags &&
      other.onlineAi == onlineAi &&
      other.showOverviewMap == showOverviewMap &&
      other.showDmrcMap == showDmrcMap &&
      other.showLiveTracking == showLiveTracking &&
      other.showMapSearch == showMapSearch;

  @override
  int get hashCode => Object.hash(
    onlineAi,
    showOverviewMap,
    showDmrcMap,
    showLiveTracking,
    showMapSearch,
  );
}
