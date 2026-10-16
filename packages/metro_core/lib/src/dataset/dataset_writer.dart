import 'dart:io';

import 'package:metro_core/src/dataset/schema.dart';
import 'package:metro_core/src/model/provenance.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:sqlite3/sqlite3.dart';

/// Writes a [MetroSnapshot] as `metro.sqlite` (schema [currentSchemaVersion]).
///
/// Used by the data pipeline; lives here so the DDL and the reader share one
/// definition. The writer does not validate - run `validateSnapshot` first.
/// Foreign keys are enforced, so structurally broken data fails to insert.
abstract final class DatasetWriter {
  /// Creates (or replaces) the SQLite file at [path].
  static void writeFile(MetroSnapshot snapshot, String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    file.parent.createSync(recursive: true);
    final db = sqlite3.open(path);
    try {
      write(snapshot, db);
    } finally {
      db.close();
    }
  }

  /// Writes into an already opened, empty [db].
  static void write(MetroSnapshot s, Database db) {
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('BEGIN');
    try {
      schemaStatements.forEach(db.execute);
      _insertAll(s, db);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    db.execute('PRAGMA user_version = $currentSchemaVersion');
  }

  static void _insertAll(MetroSnapshot s, Database db) {
    void insert<T>(
      String sql,
      Iterable<T> rows,
      List<Object?> Function(T) values,
    ) {
      final stmt = db.prepare(sql);
      try {
        for (final r in rows) {
          stmt.execute(values(r));
        }
      } finally {
        stmt.close();
      }
    }

    // Optional text/number/bool helpers.
    int? b(Object? v) => v == null ? null : ((v as bool) ? 1 : 0);
    List<Object?> prov(Provenance p) => [
      p.sourceId,
      p.confidence.wire,
      p.verifiedOn,
    ];

    insert(
      'INSERT INTO meta VALUES (?,?)',
      s.meta.entries,
      (e) => [e.key, e.value],
    );
    insert(
      'INSERT INTO source VALUES (?,?,?,?,?,?,?,?)',
      s.sources,
      (x) => [
        x.id,
        x.name,
        x.url,
        x.license,
        x.retrievedAt,
        x.notes,
        x.version,
        x.sha256,
      ],
    );
    insert(
      'INSERT INTO fare_system VALUES (?,?,?,?,?)',
      s.fareSystems,
      (x) => [x.id, x.operatorId, x.currency, x.effectiveFrom, x.sourceId],
    );
    insert(
      'INSERT INTO operator VALUES (?,?,?,?)',
      s.operators,
      (x) => [x.id, x.nameEn, x.nameHi, x.fareSystemId],
    );
    insert(
      'INSERT INTO line VALUES (?,?,?,?,?,?,?,?,?)',
      s.lines,
      (x) => [
        x.id,
        x.operatorId,
        x.nameEn,
        x.nameHi,
        x.shortName,
        x.colorHex,
        x.textColorHex,
        x.sort,
        x.status.wire,
      ],
    );
    // Services referencing another service must come after it.
    final services = [...s.services]
      ..sort(
        (a, c) => (a.throughServiceOf == null ? 0 : 1).compareTo(
          c.throughServiceOf == null ? 0 : 1,
        ),
      );
    insert(
      'INSERT INTO line_service VALUES (?,?,?,?,?)',
      services,
      (x) => [x.id, x.lineId, x.name, b(x.isLoop), x.throughServiceOf],
    );
    insert(
      'INSERT INTO station VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      s.stations,
      (x) => [
        x.id,
        x.nameEn,
        x.nameHi,
        x.lat,
        x.lng,
        x.popularity,
        x.status.wire,
        x.openedOn,
        x.mapX,
        x.mapY,
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO service_stop VALUES (?,?,?,?)',
      s.serviceStops,
      (x) => [x.serviceId, x.seq, x.stationId, x.distFromStartM],
    );
    insert(
      'INSERT INTO station_name VALUES (?,?,?,?)',
      s.stationNames,
      (x) => [x.stationId, x.text, x.lang, x.kind.wire],
    );
    insert(
      'INSERT INTO station_line VALUES (?,?,?)',
      s.stationLines,
      (x) => [x.stationId, x.lineId, x.stationCode],
    );
    insert(
      'INSERT INTO edge VALUES (?,?,?,?,?,?,?,?,?)',
      s.edges,
      (x) => [
        x.id,
        x.serviceId,
        x.fromStation,
        x.toStation,
        x.travelS,
        x.distanceM,
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO transfer VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      s.transfers,
      (x) => [
        x.stationId,
        x.fromLine,
        x.toLine,
        x.walkM,
        x.walkS,
        b(x.stepFree),
        x.notesEn,
        x.notesHi,
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO walk_link VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
      s.walkLinks,
      (x) => [
        x.id,
        x.fromStation,
        x.toStation,
        x.walkM,
        x.walkS,
        b(x.requiresExit),
        b(x.stepFree),
        x.notesEn,
        x.notesHi,
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO platform VALUES (?,?,?,?,?,?,?,?,?,?)',
      s.platforms,
      (x) => [
        x.stationId,
        x.lineId,
        x.number,
        x.towardsStationId,
        x.serviceId,
        x.notesEn,
        x.notesHi,
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO gate VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      s.gates,
      (x) => [
        x.id,
        x.stationId,
        x.number,
        x.nameEn,
        x.nameHi,
        x.lat,
        x.lng,
        b(x.isOpen),
        b(x.hasLift),
        b(x.hasRamp),
        b(x.hasEscalator),
        b(x.isStepFree),
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO gate_landmark VALUES (?,?,?,?)',
      s.gateLandmarks,
      (x) => [x.gateId, x.textEn, x.textHi, x.kind.wire],
    );
    insert(
      'INSERT INTO facility VALUES (?,?,?,?,?,?,?,?)',
      s.facilities,
      (x) => [
        x.stationId,
        x.type.wire,
        x.gateId,
        x.locationEn,
        x.locationHi,
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO accessibility VALUES (?,?,?,?,?,?,?,?,?,?)',
      s.accessibility,
      (x) => [
        x.stationId,
        x.lifts,
        x.escalators,
        b(x.tactilePath),
        b(x.wheelchairAvailable),
        x.notesEn,
        x.notesHi,
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO fare_slab VALUES (?,?,?,?,?)',
      s.fareSlabs,
      (x) => [
        x.fareSystemId,
        x.dayType.wire,
        x.minKm,
        x.maxKm,
        x.amountPaise,
      ],
    );
    insert(
      'INSERT INTO fare_discount VALUES (?,?,?,?,?)',
      s.fareDiscounts,
      (x) => [
        x.fareSystemId,
        x.media.wire,
        x.kind.wire,
        x.percent,
        x.windowsJson,
      ],
    );
    insert(
      'INSERT INTO fare_override VALUES (?,?,?,?,?,?,?)',
      s.fareOverrides,
      (x) => [
        x.fareSystemId,
        x.fromStation,
        x.toStation,
        x.dayType.wire,
        x.amountPaise,
        x.sourceId,
        x.verifiedOn,
      ],
    );
    insert(
      'INSERT INTO timing VALUES (?,?,?,?,?,?,?,?,?)',
      s.timings,
      (x) => [
        x.serviceId,
        x.stationId,
        x.directionTerminalId,
        x.dayType.wire,
        x.firstDep,
        x.lastDep,
        ...prov(x.provenance),
      ],
    );
    insert(
      'INSERT INTO origin VALUES (?,?,?,?,?,?,?)',
      s.origins,
      (x) => [
        x.entity,
        x.entityId,
        x.field,
        x.sourceId,
        x.externalId,
        x.status.wire,
        x.detail,
      ],
    );
  }
}
