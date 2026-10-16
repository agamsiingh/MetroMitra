import 'dart:io';

import 'package:data_pipeline/src/util.dart';
import 'package:yaml/yaml.dart';

class OverlayException implements Exception {
  OverlayException(this.message);
  final String message;
  @override
  String toString() => 'OverlayException: $message';
}

/// Why/who/when for a curated entry. All three are mandatory so every
/// curated override is auditable.
class Curation {
  const Curation({
    required this.reason,
    required this.source,
    required this.verifiedOn,
  });

  final String reason;
  final String source;
  final String verifiedOn;
}

class OperatorOverlay {
  const OperatorOverlay({
    required this.osmOperator,
    required this.id,
    required this.curation,
    this.nameHi,
  });

  final String osmOperator;
  final String id;
  final String? nameHi;
  final Curation curation;
}

class LineOverlay {
  const LineOverlay({
    required this.id,
    required this.curation,
    this.nameEn,
    this.nameHi,
    this.shortName,
    this.color,
  });

  final String id;
  final String? nameEn;
  final String? nameHi;
  final String? shortName;
  final String? color;
  final Curation curation;
}

class AliasOverlay {
  const AliasOverlay(this.text, this.lang, this.kind);
  final String text;
  final String lang;
  final String kind;
}

class StationOverlay {
  const StationOverlay({
    required this.id,
    required this.curation,
    this.nameEn,
    this.nameHi,
    this.lat,
    this.lng,
    this.aliases = const [],
  });

  final String id;
  final String? nameEn;
  final String? nameHi;
  final double? lat;
  final double? lng;
  final List<AliasOverlay> aliases;
  final Curation curation;
}

class StationMerge {
  const StationMerge({
    required this.id,
    required this.members,
    required this.curation,
  });

  /// Id of the merged station.
  final String id;

  /// Cluster ids (as printed in the build report) to merge.
  final List<String> members;
  final Curation curation;
}

/// Decision for one reported conflict: accept it as-is, or pick a value.
class Resolution {
  const Resolution({
    required this.conflict,
    required this.curation,
    this.accept = false,
    this.use,
  });

  final String conflict;
  final bool accept;

  /// `osm`, `wikidata`, or a literal value.
  final String? use;
  final Curation curation;
}

class Overlay {
  const Overlay({
    this.patch = 0,
    this.operators = const [],
    this.lines = const [],
    this.stations = const [],
    this.merges = const [],
    this.resolutions = const [],
    this.sha256 = '',
  });

  static const empty = Overlay();

  final int patch;
  final List<OperatorOverlay> operators;
  final List<LineOverlay> lines;
  final List<StationOverlay> stations;
  final List<StationMerge> merges;
  final List<Resolution> resolutions;

  /// Hash of the overlay file (its "version" in provenance).
  final String sha256;

  /// Sections that carry station facts. They arrive in later milestones and
  /// are rejected now so nothing unverified can slip in.
  static const reservedSections = [
    'gates',
    'platforms',
    'facilities',
    'accessibility',
    'parking',
    'fares',
    'timings',
  ];

  static Overlay load(String path) {
    final f = File(path);
    if (!f.existsSync()) return Overlay.empty;
    return parse(f.readAsStringSync());
  }

  static Overlay parse(String text) {
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      throw OverlayException('overlay is not valid YAML: ${e.message}');
    }
    if (doc == null) return Overlay(sha256: sha256Hex(text.codeUnits));
    if (doc is! YamlMap) throw OverlayException('overlay must be a map');
    final root = _Node(doc, 'overlay');

    for (final key in reservedSections) {
      if (doc.containsKey(key)) {
        throw OverlayException(
          '"$key" is reserved for a later milestone and cannot be imported '
          'yet (M2 never adds gates, platforms, facilities, fares, timings '
          'or parking)',
        );
      }
    }
    final release = root.optMap('release');
    final overlay = Overlay(
      patch: release?.optInt('patch') ?? 0,
      operators: [
        for (final o in root.list('operators'))
          OperatorOverlay(
            osmOperator: o.str('osm_operator'),
            id: o.str('id'),
            nameHi: o.optStr('name_hi'),
            curation: o.curation(),
          ),
      ],
      lines: [
        for (final o in root.list('lines'))
          LineOverlay(
            id: o.str('id'),
            nameEn: o.optStr('name_en'),
            nameHi: o.optStr('name_hi'),
            shortName: o.optStr('short_name'),
            color: o.optStr('color'),
            curation: o.curation(),
          ),
      ],
      stations: [
        for (final o in root.list('stations'))
          StationOverlay(
            id: o.str('id'),
            nameEn: o.optStr('name_en'),
            nameHi: o.optStr('name_hi'),
            lat: o.optNum('lat'),
            lng: o.optNum('lng'),
            aliases: [
              for (final a in o.list('aliases'))
                AliasOverlay(a.str('text'), a.str('lang'), a.str('kind')),
            ],
            curation: o.curation(),
          ),
      ],
      merges: [
        for (final o in root.list('station_merges'))
          StationMerge(
            id: o.str('id'),
            members: o.strList('members'),
            curation: o.curation(),
          ),
      ],
      resolutions: [
        for (final o in root.list('resolutions'))
          Resolution(
            conflict: o.str('conflict'),
            accept: o.optBool('accept') ?? false,
            use: o.optStr('use'),
            curation: o.curation(),
          ),
      ],
      sha256: sha256Hex(text.codeUnits),
    );
    root.checkUnknownKeys();
    for (final r in overlay.resolutions) {
      if (r.accept == (r.use != null)) {
        throw OverlayException(
          'resolution for "${r.conflict}": give exactly one of accept/use',
        );
      }
    }
    for (final m in overlay.merges) {
      if (m.members.length < 2) {
        throw OverlayException('merge "${m.id}" needs at least 2 members');
      }
    }
    return overlay;
  }
}

class _Node {
  _Node(this.m, this.path, [List<_Node>? all]) : _all = all ?? [] {
    _all.add(this);
  }

  final YamlMap m;
  final String path;
  final List<_Node> _all;
  final Set<String> _used = {};

  Object? _get(String k) {
    _used.add(k);
    return m[k];
  }

  OverlayException _bad(String k, String want) =>
      OverlayException('$path.$k: expected $want');

  String str(String k) {
    final v = _get(k);
    if (v == null) throw OverlayException('$path: missing "$k"');
    return v is String ? v : throw _bad(k, 'string');
  }

  String? optStr(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is String ? v : throw _bad(k, 'string');
  }

  int? optInt(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is int ? v : throw _bad(k, 'integer');
  }

  double? optNum(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is num ? v.toDouble() : throw _bad(k, 'number');
  }

  bool? optBool(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is bool ? v : throw _bad(k, 'boolean');
  }

  List<String> strList(String k) {
    final v = _get(k);
    if (v is! YamlList) throw _bad(k, 'list of strings');
    return [for (final x in v) x is String ? x : throw _bad(k, 'strings')];
  }

  _Node? optMap(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is YamlMap ? _Node(v, '$path.$k', _all) : throw _bad(k, 'map');
  }

  List<_Node> list(String k) {
    final v = _get(k);
    if (v == null) return const [];
    if (v is! YamlList) throw _bad(k, 'list');
    return [
      for (var i = 0; i < v.length; i++)
        v[i] is YamlMap
            ? _Node(v[i] as YamlMap, '$path.$k[$i]', _all)
            : throw OverlayException('$path.$k[$i]: must be a map'),
    ];
  }

  /// reason + source + verified_on are all required (and ISO-dated).
  Curation curation() {
    final verified = str('verified_on');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(verified)) {
      throw OverlayException('$path.verified_on: expected YYYY-MM-DD');
    }
    return Curation(
      reason: str('reason'),
      source: str('source'),
      verifiedOn: verified,
    );
  }

  void checkUnknownKeys() {
    for (final n in _all) {
      final unknown = n.m.keys
          .map((k) => '$k')
          .where((k) => !n._used.contains(k));
      if (unknown.isNotEmpty) {
        throw OverlayException(
          '${n.path}: unknown key(s) ${unknown.join(', ')}',
        );
      }
    }
  }
}
