import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/src/overlay.dart';
import 'package:data_pipeline/src/util.dart';

/// Approved rows exported from the admin panel (`npm run export`,
/// format `metromitra-curated/1`). Station names, Hindi names, aliases and
/// coordinates become station overlays; the other tables are counted and
/// reported as not imported until the dataset schema has a place for them
/// (ADR-029). Nothing is imported without source + verified_on + confidence.
class AdminImport {
  const AdminImport({
    this.stations = const [],
    this.notImported = const {},
    this.sha256 = '',
    this.file,
  });

  factory AdminImport.load(String path) {
    final f = File(path);
    if (!f.existsSync()) return AdminImport.empty;
    return AdminImport.parse(f.readAsStringSync(), file: path);
  }

  factory AdminImport.parse(String text, {String? file}) {
    final Object? doc;
    try {
      doc = jsonDecode(text);
    } on FormatException catch (e) {
      throw OverlayException('admin export is not valid JSON: ${e.message}');
    }
    if (doc is! Map<String, Object?> || doc['format'] != format) {
      throw OverlayException('admin export: expected format "$format"');
    }
    final tables = doc['tables'];
    if (tables is! Map<String, Object?>) {
      throw OverlayException('admin export: "tables" must be a map');
    }
    final stations = <StationOverlay>[];
    final notImported = <String, int>{};
    for (final MapEntry(key: table, value: rows) in tables.entries) {
      if (rows is! List) {
        throw OverlayException('admin export: $table must be a list');
      }
      if (table != 'curated_stations') {
        if (rows.isNotEmpty) notImported[table] = rows.length;
        continue;
      }
      for (var i = 0; i < rows.length; i++) {
        stations.add(_station(rows[i], 'curated_stations[$i]'));
      }
    }
    final ids = <String>{};
    for (final s in stations) {
      if (!ids.add(s.id)) {
        throw OverlayException('admin export: station "${s.id}" appears twice');
      }
    }
    return AdminImport(
      stations: stations,
      notImported: notImported,
      sha256: sha256Hex(utf8.encode(text)),
      file: file,
    );
  }

  static const empty = AdminImport();
  static const format = 'metromitra-curated/1';

  final List<StationOverlay> stations;

  /// table -> approved rows that the pipeline cannot import yet.
  final Map<String, int> notImported;
  final String sha256;
  final String? file;

  static StationOverlay _station(Object? row, String path) {
    if (row is! Map<String, Object?>) {
      throw OverlayException('$path: must be an object');
    }
    String? str(String k) {
      final v = row[k];
      if (v == null) return null;
      if (v is! String) throw OverlayException('$path.$k: expected string');
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    double? num_(String k) {
      final v = row[k];
      if (v == null) return null;
      if (v is! num) throw OverlayException('$path.$k: expected number');
      return v.toDouble();
    }

    final id =
        str('station_id') ??
        (throw OverlayException('$path: missing station_id'));
    final source = str('source');
    final verified = str('verified_on');
    final confidence = str('confidence');
    if (source == null || verified == null || confidence == null) {
      throw OverlayException(
        '$path ($id): approved rows need source, verified_on and confidence',
      );
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(verified)) {
      throw OverlayException('$path.verified_on: expected YYYY-MM-DD');
    }
    final aliasesRaw = row['aliases'] ?? const <Object?>[];
    if (aliasesRaw is! List) {
      throw OverlayException('$path.aliases: expected a list');
    }
    final aliases = <AliasOverlay>[];
    for (var i = 0; i < aliasesRaw.length; i++) {
      final a = aliasesRaw[i];
      if (a is! Map<String, Object?> ||
          a['text'] is! String ||
          (a['text']! as String).trim().isEmpty) {
        throw OverlayException('$path.aliases[$i]: needs "text"');
      }
      final lang = a['lang'] ?? 'en';
      if (lang != 'en' && lang != 'hi') {
        throw OverlayException('$path.aliases[$i].lang: en or hi');
      }
      final kind = a['kind'] ?? 'alias';
      if (kind is! String) {
        throw OverlayException('$path.aliases[$i].kind: expected string');
      }
      aliases.add(
        AliasOverlay((a['text']! as String).trim(), lang as String, kind),
      );
    }
    final note = str('note');
    return StationOverlay(
      id: id,
      nameEn: str('name_en'),
      nameHi: str('name_hi'),
      lat: num_('lat'),
      lng: num_('lng'),
      aliases: aliases,
      curation: Curation(
        reason: 'admin panel ($confidence)${note == null ? '' : ': $note'}',
        source: source,
        verifiedOn: verified,
      ),
    );
  }
}
