import 'dart:convert';

import 'package:data_pipeline/src/config.dart';
import 'package:data_pipeline/src/util.dart';

/// The raw input cannot be parsed into the expected shape.
class SourceFormatException implements Exception {
  SourceFormatException(this.source, this.message);
  final String source;
  final String message;
  @override
  String toString() => 'SourceFormatException($source): $message';
}

/// A recoverable problem found while normalising; surfaced as a conflict.
class NormalizationIssue {
  const NormalizationIssue(this.code, this.subject, this.message);
  final String code;
  final String subject;
  final String message;
}

// ---------------------------------------------------------------- OSM

class OsmStop {
  const OsmStop({
    required this.nodeId,
    required this.name,
    required this.lat,
    required this.lng,
    this.nameHi,
    this.wikidata,
    this.ref,
    this.altNames = const [],
    this.altNamesHi = const [],
    this.oldNames = const [],
  });

  final int nodeId;
  final String name;
  final String? nameHi;
  final double lat;
  final double lng;
  final String? wikidata;

  /// Station code tag (`ref`), if present.
  final String? ref;
  final List<String> altNames;
  final List<String> altNamesHi;
  final List<String> oldNames;
}

class OsmRoute {
  const OsmRoute({
    required this.id,
    required this.name,
    required this.stops,
    this.ref,
    this.colour,
    this.operator,
    this.lineWikidata,
  });

  final int id;
  final String name;
  final String? ref;

  /// `#RRGGBB` upper-case, or null if the tag is absent/not a hex colour.
  final String? colour;
  final String? operator;

  /// Wikidata item of the *line* (relation `wikidata` tag).
  final String? lineWikidata;

  /// Stop nodes in route order.
  final List<OsmStop> stops;
}

class OsmData {
  const OsmData({
    required this.routes,
    required this.issues,
    this.baseTimestamp,
  });

  final List<OsmRoute> routes;
  final List<NormalizationIssue> issues;
  final String? baseTimestamp;
}

String? _tag(Map<String, Object?> tags, String key) {
  final v = tags[key];
  if (v is! String) return null;
  final t = tidy(v);
  return t.isEmpty ? null : t;
}

List<String> _multi(Map<String, Object?> tags, String key) {
  final v = _tag(tags, key);
  if (v == null) return const [];
  return [
    for (final p in v.split(';'))
      if (tidy(p).isNotEmpty) tidy(p),
  ];
}

final _hexColour = RegExp(r'^#([0-9a-fA-F]{6})$');
final _shortHex = RegExp(r'^#([0-9a-fA-F]{3})$');

/// `#abc` / `#aabbcc` -> `#AABBCC`; anything else (names, junk) -> null.
String? normalizeColour(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (_hexColour.hasMatch(t)) return t.toUpperCase();
  final m = _shortHex.firstMatch(t);
  if (m != null) {
    return '#${m.group(1)!.split('').map((c) => '$c$c').join().toUpperCase()}';
  }
  return null;
}

/// Parses an Overpass JSON answer into routes with their ordered stop nodes.
/// Throws [SourceFormatException] if the structure is not Overpass JSON.
/// Problems in individual relations (missing nodes, unnamed stops) are
/// returned as [OsmData.issues], never swallowed.
OsmData normalizeOsm(List<int> bytes, {required String network}) {
  const src = 'osm-overpass';
  final Object? doc;
  try {
    doc = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    throw SourceFormatException(src, 'not valid JSON: ${e.message}');
  }
  if (doc is! Map) {
    throw SourceFormatException(src, 'top level is not an object');
  }
  final elements = doc['elements'];
  if (elements is! List) {
    throw SourceFormatException(src, 'no elements array');
  }

  final nodes = <int, Map<String, Object?>>{};
  final relations = <Map<String, Object?>>[];
  for (var i = 0; i < elements.length; i++) {
    final e = elements[i];
    if (e is! Map || e['type'] is! String || e['id'] is! int) {
      throw SourceFormatException(src, 'element #$i has no type/id');
    }
    final m = e.cast<String, Object?>();
    if (e['type'] == 'node') {
      nodes[e['id'] as int] = m;
    } else if (e['type'] == 'relation') {
      relations.add(m);
    }
  }

  final issues = <NormalizationIssue>[];
  final routes = <OsmRoute>[];
  relations.sort((a, b) => (a['id']! as int).compareTo(b['id']! as int));
  for (final r in relations) {
    final id = r['id']! as int;
    final tags = (r['tags'] is Map
        ? (r['tags']! as Map).cast<String, Object?>()
        : <String, Object?>{});
    if (tags['route'] != 'subway' || tags['network'] != network) continue;
    final subject = 'osm-relation/$id';
    final members = r['members'];
    if (members is! List) {
      throw SourceFormatException(src, 'relation $id has no members array');
    }
    final stops = <OsmStop>[];
    for (final m in members) {
      if (m is! Map || m['type'] != 'node' || m['role'] != 'stop') continue;
      final ref = m['ref'];
      final node = ref is int ? nodes[ref] : null;
      if (node == null) {
        issues.add(
          NormalizationIssue(
            'missing-node',
            subject,
            'stop node $ref of relation $id is absent from the download',
          ),
        );
        continue;
      }
      final nt = (node['tags'] is Map
          ? (node['tags']! as Map).cast<String, Object?>()
          : <String, Object?>{});
      final name = _tag(nt, 'name');
      final lat = node['lat'];
      final lng = node['lon'];
      if (name == null || lat is! num || lng is! num) {
        issues.add(
          NormalizationIssue(
            'bad-stop',
            'osm-node/$ref',
            'stop node $ref (relation $id) has no name or coordinates',
          ),
        );
        continue;
      }
      stops.add(
        OsmStop(
          nodeId: ref as int,
          name: name,
          nameHi: _tag(nt, 'name:hi'),
          lat: round6(lat.toDouble()),
          lng: round6(lng.toDouble()),
          wikidata: _tag(nt, 'wikidata'),
          ref: _tag(nt, 'ref'),
          altNames: _multi(nt, 'alt_name'),
          altNamesHi: _multi(nt, 'alt_name:hi'),
          oldNames: _multi(nt, 'old_name'),
        ),
      );
    }
    final fullName = _tag(tags, 'name') ?? 'relation $id';
    final colourRaw = _tag(tags, 'colour');
    final colour = normalizeColour(colourRaw);
    if (colourRaw != null && colour == null) {
      issues.add(
        NormalizationIssue(
          'bad-colour',
          subject,
          'colour "$colourRaw" is not a hex colour; ignored',
        ),
      );
    }
    if (stops.length < 2) {
      issues.add(
        NormalizationIssue(
          'short-route',
          subject,
          'relation $id has ${stops.length} usable stop(s); skipped',
        ),
      );
      continue;
    }
    routes.add(
      OsmRoute(
        id: id,
        name: fullName,
        ref: _tag(tags, 'ref'),
        colour: colour,
        operator: _tag(tags, 'operator'),
        lineWikidata: _tag(tags, 'wikidata'),
        stops: stops,
      ),
    );
  }
  final osm3s = doc['osm3s'];
  return OsmData(
    routes: routes,
    issues: issues,
    baseTimestamp: osm3s is Map ? osm3s['timestamp_osm_base'] as String? : null,
  );
}

// ---------------------------------------------------------------- Wikidata

class WdLine {
  const WdLine(this.qid, {this.labelEn, this.labelHi});
  final String qid;
  final String? labelEn;
  final String? labelHi;
}

class WdStation {
  const WdStation({
    required this.qid,
    this.labelEn,
    this.labelHi,
    this.lat,
    this.lng,
    this.lines = const [],
  });

  final String qid;

  /// Labels with configured suffixes (" metro station") removed.
  final String? labelEn;
  final String? labelHi;
  final double? lat;
  final double? lng;
  final List<WdLine> lines;
}

class WdData {
  const WdData(this.stations);
  final Map<String, WdStation> stations;

  /// Line labels by line QID, merged over all stations.
  Map<String, WdLine> get lines {
    final out = <String, WdLine>{};
    for (final s in stations.values) {
      for (final l in s.lines) {
        final prev = out[l.qid];
        out[l.qid] = WdLine(
          l.qid,
          labelEn: prev?.labelEn ?? l.labelEn,
          labelHi: prev?.labelHi ?? l.labelHi,
        );
      }
    }
    return out;
  }
}

String qidOf(String entityUri) => entityUri.split('/').last;

String stripSuffixes(String text, List<String> suffixes) {
  var out = tidy(text);
  var changed = true;
  while (changed) {
    changed = false;
    for (final s in suffixes) {
      if (out.toLowerCase().endsWith(s.toLowerCase()) &&
          out.length > s.length) {
        out = tidy(out.substring(0, out.length - s.length));
        changed = true;
      }
    }
  }
  return out;
}

final _point = RegExp(r'^Point\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\)$');

/// Parses SPARQL JSON results (one row per station x line) into stations.
WdData normalizeWikidata(List<int> bytes, NormalizationRules rules) {
  const src = 'wikidata';
  final Object? doc;
  try {
    doc = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    throw SourceFormatException(src, 'not valid JSON: ${e.message}');
  }
  final results = doc is Map ? doc['results'] : null;
  final bindings = results is Map ? results['bindings'] : null;
  if (bindings is! List) {
    throw SourceFormatException(src, 'no results.bindings');
  }

  String? val(Map<Object?, Object?> row, String key) {
    final cell = row[key];
    final v = cell is Map ? cell['value'] : null;
    return v is String ? v : null;
  }

  final labelsEn = <String, String>{};
  final labelsHi = <String, String>{};
  final coords = <String, (double, double)>{};
  final lines = <String, Map<String, WdLine>>{};
  for (var i = 0; i < bindings.length; i++) {
    final row = bindings[i];
    if (row is! Map) {
      throw SourceFormatException(src, 'row #$i is not an object');
    }
    final item = val(row, 'item');
    if (item == null) {
      throw SourceFormatException(src, 'row #$i has no item');
    }
    final qid = qidOf(item);
    final en = val(row, 'itemLabel_en');
    final hi = val(row, 'itemLabel_hi');
    if (en != null) labelsEn[qid] = stripSuffixes(en, rules.stripSuffixesEn);
    if (hi != null) labelsHi[qid] = stripSuffixes(hi, rules.stripSuffixesHi);
    final p = val(row, 'coord');
    final m = p == null ? null : _point.firstMatch(p);
    if (m != null) {
      coords[qid] = (double.parse(m.group(2)!), double.parse(m.group(1)!));
    }
    final line = val(row, 'line');
    if (line != null) {
      final lq = qidOf(line);
      lines.putIfAbsent(qid, () => {})[lq] = WdLine(
        lq,
        labelEn: val(row, 'lineLabel_en'),
        labelHi: val(row, 'lineLabel_hi'),
      );
    } else {
      lines.putIfAbsent(qid, () => {});
    }
  }
  final qids = lines.keys.toList()..sort();
  return WdData({
    for (final q in qids)
      q: WdStation(
        qid: q,
        labelEn: labelsEn[q],
        labelHi: labelsHi[q],
        lat: coords[q]?.$1,
        lng: coords[q]?.$2,
        lines: (lines[q]!.values.toList()
          ..sort((a, b) => a.qid.compareTo(b.qid))),
      ),
  });
}
