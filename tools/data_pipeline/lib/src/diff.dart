import 'package:data_pipeline/src/util.dart';
import 'package:metro_core/metro_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// Table-level change set keyed by primary key.
class TableDiff {
  TableDiff(this.table);

  final String table;
  final List<String> added = [];
  final List<String> removed = [];

  /// key -> {column: [old, new]}
  final Map<String, Map<String, List<Object?>>> changed = {};

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;

  Map<String, Object?> toJson() => {
    'added': added,
    'removed': removed,
    'changed': changed,
  };
}

/// Difference between two datasets, grouped the way a changelog reads.
class DatasetDiff {
  DatasetDiff(this.tables, this.coordinateMoves);

  final Map<String, TableDiff> tables;

  /// station id -> metres moved (only where lat/lng changed).
  final Map<String, int> coordinateMoves;

  TableDiff _t(String name) => tables[name] ?? TableDiff(name);

  List<String> get stationsAdded => _t('station').added;
  List<String> get stationsRemoved => _t('station').removed;

  /// station id -> {name_en|name_hi: [old, new]}
  Map<String, Map<String, List<Object?>>> get stationsRenamed => {
    for (final e in _t('station').changed.entries)
      if (e.value.keys.any((k) => k == 'name_en' || k == 'name_hi'))
        e.key: {
          for (final c in e.value.entries)
            if (c.key == 'name_en' || c.key == 'name_hi') c.key: c.value,
        },
  };

  /// Lines (and their services/operators) added, removed or edited.
  Map<String, TableDiff> get lineChanges => {
    for (final t in const ['operator', 'line', 'line_service'])
      if (!_t(t).isEmpty) t: _t(t),
  };

  /// Who-connects-to-whom: line membership, stop order, edges, interchanges.
  Map<String, TableDiff> get relationshipChanges => {
    for (final t in const [
      'station_line',
      'service_stop',
      'edge',
      'transfer',
      'walk_link',
    ])
      if (!_t(t).isEmpty) t: _t(t),
  };

  /// Hand-curated station facts (never produced by M2 itself).
  Map<String, TableDiff> get curatedFactChanges => {
    for (final t in const [
      'gate',
      'gate_landmark',
      'platform',
      'facility',
      'accessibility',
      'fare_system',
      'fare_slab',
      'fare_discount',
      'fare_override',
      'timing',
    ])
      if (!_t(t).isEmpty) t: _t(t),
  };

  /// Curated overrides recorded in `origin` that appeared/disappeared/changed.
  TableDiff get originChanges => _t('origin');

  bool get isEmpty => tables.values.every((t) => t.isEmpty);

  Map<String, Object?> toJson() => {
    'empty': isEmpty,
    'stations_added': stationsAdded,
    'stations_removed': stationsRemoved,
    'stations_renamed': stationsRenamed,
    'coordinates_changed_m': coordinateMoves,
    'tables': {
      for (final e in tables.entries)
        if (!e.value.isEmpty) e.key: e.value.toJson(),
    },
  };

  /// Human-readable changelog (sections only when non-empty).
  String toText({int examples = 10}) {
    if (isEmpty) return 'No differences.';
    final out = StringBuffer();
    void section(String title, Iterable<String> lines) {
      final list = lines.toList();
      if (list.isEmpty) return;
      out.writeln('$title (${list.length})');
      for (final l in list.take(examples)) {
        out.writeln('  - $l');
      }
      if (list.length > examples) {
        out.writeln('  ... ${list.length - examples} more');
      }
    }

    section('Stations added', stationsAdded);
    section('Stations removed', stationsRemoved);
    section('Stations renamed', [
      for (final e in stationsRenamed.entries)
        '${e.key}: ${e.value.entries.map((c) => '${c.key} "${c.value[0]}" -> "${c.value[1]}"').join(', ')}',
    ]);
    section('Coordinates changed', [
      for (final e in coordinateMoves.entries) '${e.key}: moved ${e.value} m',
    ]);
    for (final e in lineChanges.entries) {
      section('Changed ${e.key}', _describe(e.value));
    }
    for (final e in relationshipChanges.entries) {
      section('Changed relationships: ${e.key}', _describe(e.value));
    }
    for (final e in curatedFactChanges.entries) {
      section('Changed curated facts: ${e.key}', _describe(e.value));
    }
    section('Changed provenance (origin)', _describe(originChanges));
    for (final t in const ['meta', 'source']) {
      section('Changed $t', _describe(_t(t)));
    }
    return out.toString();
  }

  static Iterable<String> _describe(TableDiff d) sync* {
    for (final k in d.added) {
      yield '+ $k';
    }
    for (final k in d.removed) {
      yield '- $k';
    }
    for (final e in d.changed.entries) {
      yield '~ ${e.key}: ${e.value.entries.map((c) => '${c.key} ${c.value[0]} -> ${c.value[1]}').join(', ')}';
    }
  }
}

/// Compares two dataset databases table by table (schema v1 tables).
DatasetDiff diffDatabases(Database oldDb, Database newDb) {
  final tables = <String, TableDiff>{};
  for (final table in schemaTables) {
    final a = _rows(oldDb, table);
    final b = _rows(newDb, table);
    final d = TableDiff(table);
    for (final k in a.keys) {
      if (!b.containsKey(k)) d.removed.add(k);
    }
    for (final k in b.keys) {
      if (!a.containsKey(k)) {
        d.added.add(k);
      } else {
        final cols = <String, List<Object?>>{};
        for (final c in b[k]!.keys) {
          if (a[k]![c] != b[k]![c]) cols[c] = [a[k]![c], b[k]![c]];
        }
        if (cols.isNotEmpty) d.changed[k] = cols;
      }
    }
    d.added.sort();
    d.removed.sort();
    if (!d.isEmpty) tables[table] = d;
  }

  final moves = <String, int>{};
  final st = tables['station'];
  if (st != null) {
    for (final e in st.changed.entries) {
      final c = e.value;
      if (c.containsKey('lat') || c.containsKey('lng')) {
        final row = _rows(oldDb, 'station')[e.key]!;
        final nrow = _rows(newDb, 'station')[e.key]!;
        moves[e.key] = haversineM(
          (row['lat']! as num).toDouble(),
          (row['lng']! as num).toDouble(),
          (nrow['lat']! as num).toDouble(),
          (nrow['lng']! as num).toDouble(),
        ).round();
      }
    }
  }
  return DatasetDiff(tables, moves);
}

/// Opens both files read-only and compares them.
DatasetDiff diffFiles(String oldPath, String newPath) {
  final a = sqlite3.open(oldPath, mode: OpenMode.readOnly);
  try {
    final b = sqlite3.open(newPath, mode: OpenMode.readOnly);
    try {
      return diffDatabases(a, b);
    } finally {
      b.close();
    }
  } finally {
    a.close();
  }
}

Map<String, Map<String, Object?>> _rows(Database db, String table) {
  // A corrupt/non-database file must fail loudly, not look like "all rows added".
  final info = db.select('PRAGMA table_info($table)');
  if (info.isEmpty) return {}; // table absent in this dataset
  final pk = info.where((c) => (c['pk'] as int) > 0).toList()
    ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
  final out = <String, Map<String, Object?>>{};
  for (final row in db.select('SELECT * FROM $table')) {
    final map = {for (final c in row.keys) c: row[c]};
    final key = pk.isEmpty
        ? map.values.join('|')
        : pk.map((c) => '${row[c['name']]}').join('|');
    out[key] = map;
  }
  return out;
}
