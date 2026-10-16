import 'dart:io';

import 'package:metro_core/src/dataset/schema.dart';
import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/fare.dart';
import 'package:metro_core/src/model/network.dart';
import 'package:metro_core/src/model/provenance.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/model/station_facts.dart';
import 'package:metro_core/src/validation/validation.dart';
import 'package:sqlite3/sqlite3.dart';

enum DatasetFailure {
  /// File absent or not a SQLite database.
  unreadable,

  /// `schema_version` is outside the range this build supports.
  incompatibleSchema,

  /// A table/column is missing or a row has an unknown value.
  malformed,

  /// Loaded fine but failed `validateSnapshot`.
  invalid,
}

class DatasetException implements Exception {
  DatasetException(this.failure, this.message, {this.report});

  final DatasetFailure failure;
  final String message;

  /// Present when [failure] is [DatasetFailure.invalid].
  final ValidationReport? report;

  @override
  String toString() => 'DatasetException(${failure.name}): $message';
}

/// Loads `metro.sqlite` into an immutable [MetroSnapshot].
///
/// Order of checks (cheapest first, so a bad file never reaches the parser):
/// readable -> `user_version` compatible -> tables parse -> validation.
abstract final class DatasetReader {
  /// Opens [path] read-only. With [validate] (default) the snapshot must pass
  /// `validateSnapshot` or a [DatasetException] with the report is thrown.
  static MetroSnapshot readFile(
    String path, {
    bool validate = true,
    ValidationMode mode = ValidationMode.release,
  }) {
    if (!File(path).existsSync()) {
      throw DatasetException(DatasetFailure.unreadable, 'No file at $path');
    }
    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw DatasetException(DatasetFailure.unreadable, e.message);
    }
    try {
      return read(db, validate: validate, mode: mode);
    } finally {
      db.close();
    }
  }

  static MetroSnapshot read(
    Database db, {
    bool validate = true,
    ValidationMode mode = ValidationMode.release,
  }) {
    try {
      final version = _schemaVersion(db);
      if (version < minSupportedSchemaVersion ||
          version > currentSchemaVersion) {
        throw DatasetException(
          DatasetFailure.incompatibleSchema,
          'schema_version $version not in '
          '[$minSupportedSchemaVersion, $currentSchemaVersion]',
        );
      }
      final snapshot = _load(db);
      if (snapshot.schemaVersion != version) {
        throw DatasetException(
          DatasetFailure.malformed,
          'meta.schema_version (${snapshot.schemaVersion}) disagrees with '
          'PRAGMA user_version ($version)',
        );
      }
      if (validate) {
        final report = validateSnapshot(snapshot, mode: mode);
        if (!report.isValid) {
          throw DatasetException(
            DatasetFailure.invalid,
            '${report.errors.length} validation error(s); first: '
            '${report.errors.first}',
            report: report,
          );
        }
      }
      return snapshot;
    } on SqliteException catch (e) {
      // Not a database, or missing table/column.
      final notDb = e.message.contains('not a database');
      throw DatasetException(
        notDb ? DatasetFailure.unreadable : DatasetFailure.malformed,
        e.message,
      );
    } on FormatException catch (e) {
      throw DatasetException(DatasetFailure.malformed, e.message);
    }
  }

  static int _schemaVersion(Database db) =>
      db.select('PRAGMA user_version').first.columnAt(0) as int;

  static MetroSnapshot _load(Database db) {
    List<T> rows<T>(String table, T Function(Row r) map, [String? order]) => [
      for (final r in db.select('SELECT * FROM $table ${order ?? ''}')) map(r),
    ];
    bool? b(Object? v) => v == null ? null : (v as int) != 0;
    Provenance prov(Row r) => Provenance(
      sourceId: r['source_id'] as String,
      confidence: Confidence.parse(r['confidence'] as String),
      verifiedOn: r['verified_on'] as String?,
    );

    return MetroSnapshot(
      meta: {
        for (final r in db.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      },
      sources: rows(
        'source',
        (r) => Source(
          id: r['id'] as String,
          name: r['name'] as String,
          url: r['url'] as String?,
          license: r['license'] as String,
          retrievedAt: r['retrieved_at'] as String?,
          notes: r['notes'] as String?,
          version: r['version'] as String?,
          sha256: r['sha256'] as String?,
        ),
        'ORDER BY id',
      ),
      fareSystems: rows(
        'fare_system',
        (r) => FareSystem(
          id: r['id'] as String,
          operatorId: r['operator_id'] as String,
          currency: r['currency'] as String,
          effectiveFrom: r['effective_from'] as String,
          sourceId: r['source_id'] as String,
        ),
        'ORDER BY id',
      ),
      operators: rows(
        'operator',
        (r) => Operator(
          id: r['id'] as String,
          nameEn: r['name_en'] as String,
          nameHi: r['name_hi'] as String?,
          fareSystemId: r['fare_system_id'] as String?,
        ),
        'ORDER BY id',
      ),
      lines: rows(
        'line',
        (r) => Line(
          id: r['id'] as String,
          operatorId: r['operator_id'] as String,
          nameEn: r['name_en'] as String,
          nameHi: r['name_hi'] as String?,
          shortName: r['short_name'] as String?,
          colorHex: r['color_hex'] as String,
          textColorHex: r['text_color_hex'] as String,
          sort: r['sort'] as int,
          status: OperatingStatus.parse(r['status'] as String),
        ),
        'ORDER BY sort, id',
      ),
      services: rows(
        'line_service',
        (r) => LineService(
          id: r['id'] as String,
          lineId: r['line_id'] as String,
          name: r['name'] as String,
          isLoop: b(r['is_loop'])!,
          throughServiceOf: r['through_service_of'] as String?,
        ),
        'ORDER BY id',
      ),
      serviceStops: rows(
        'service_stop',
        (r) => ServiceStop(
          serviceId: r['service_id'] as String,
          seq: r['seq'] as int,
          stationId: r['station_id'] as String,
          distFromStartM: r['dist_from_start_m'] as int,
        ),
        'ORDER BY service_id, seq',
      ),
      stations: rows(
        'station',
        (r) => Station(
          id: r['id'] as String,
          nameEn: r['name_en'] as String,
          nameHi: r['name_hi'] as String?,
          lat: (r['lat'] as num).toDouble(),
          lng: (r['lng'] as num).toDouble(),
          popularity: r['popularity'] as int,
          status: OperatingStatus.parse(r['status'] as String),
          openedOn: r['opened_on'] as String?,
          mapX: (r['map_x'] as num?)?.toDouble(),
          mapY: (r['map_y'] as num?)?.toDouble(),
          provenance: prov(r),
        ),
        'ORDER BY id',
      ),
      stationNames: rows(
        'station_name',
        (r) => StationName(
          stationId: r['station_id'] as String,
          text: r['text'] as String,
          lang: r['lang'] as String,
          kind: NameKind.parse(r['kind'] as String),
        ),
        'ORDER BY station_id, kind, lang, text',
      ),
      stationLines: rows(
        'station_line',
        (r) => StationLine(
          stationId: r['station_id'] as String,
          lineId: r['line_id'] as String,
          stationCode: r['station_code'] as String?,
        ),
        'ORDER BY station_id, line_id',
      ),
      edges: rows(
        'edge',
        (r) => Edge(
          id: r['id'] as String,
          serviceId: r['service_id'] as String,
          fromStation: r['from_station'] as String,
          toStation: r['to_station'] as String,
          travelS: r['travel_s'] as int?,
          distanceM: r['distance_m'] as int,
          provenance: prov(r),
        ),
        'ORDER BY id',
      ),
      transfers: rows(
        'transfer',
        (r) => Transfer(
          stationId: r['station_id'] as String,
          fromLine: r['from_line'] as String,
          toLine: r['to_line'] as String,
          walkM: r['walk_m'] as int?,
          walkS: r['walk_s'] as int?,
          stepFree: b(r['step_free']),
          notesEn: r['notes_en'] as String?,
          notesHi: r['notes_hi'] as String?,
          provenance: prov(r),
        ),
        'ORDER BY station_id, from_line, to_line',
      ),
      walkLinks: rows(
        'walk_link',
        (r) => WalkLink(
          id: r['id'] as String,
          fromStation: r['from_station'] as String,
          toStation: r['to_station'] as String,
          walkM: r['walk_m'] as int,
          walkS: r['walk_s'] as int,
          requiresExit: b(r['requires_exit'])!,
          stepFree: b(r['step_free']),
          notesEn: r['notes_en'] as String?,
          notesHi: r['notes_hi'] as String?,
          provenance: prov(r),
        ),
        'ORDER BY id',
      ),
      platforms: rows(
        'platform',
        (r) => Platform(
          stationId: r['station_id'] as String,
          lineId: r['line_id'] as String,
          number: r['number'] as String,
          towardsStationId: r['towards_station_id'] as String?,
          serviceId: r['service_id'] as String?,
          notesEn: r['notes_en'] as String?,
          notesHi: r['notes_hi'] as String?,
          provenance: prov(r),
        ),
        'ORDER BY station_id, line_id, number',
      ),
      gates: rows(
        'gate',
        (r) => Gate(
          id: r['id'] as String,
          stationId: r['station_id'] as String,
          number: r['number'] as int,
          nameEn: r['name_en'] as String?,
          nameHi: r['name_hi'] as String?,
          lat: (r['lat'] as num?)?.toDouble(),
          lng: (r['lng'] as num?)?.toDouble(),
          isOpen: b(r['is_open']),
          hasLift: b(r['has_lift']),
          hasRamp: b(r['has_ramp']),
          hasEscalator: b(r['has_escalator']),
          isStepFree: b(r['is_step_free']),
          provenance: prov(r),
        ),
        'ORDER BY station_id, number',
      ),
      gateLandmarks: rows(
        'gate_landmark',
        (r) => GateLandmark(
          gateId: r['gate_id'] as String,
          textEn: r['text_en'] as String,
          textHi: r['text_hi'] as String?,
          kind: GateLandmarkKind.parse(r['kind'] as String),
        ),
        'ORDER BY gate_id, text_en',
      ),
      facilities: rows(
        'facility',
        (r) => Facility(
          stationId: r['station_id'] as String,
          type: FacilityType.parse(r['type'] as String),
          gateId: r['gate_id'] as String?,
          locationEn: r['location_en'] as String?,
          locationHi: r['location_hi'] as String?,
          provenance: prov(r),
        ),
        'ORDER BY station_id, type',
      ),
      accessibility: rows(
        'accessibility',
        (r) => Accessibility(
          stationId: r['station_id'] as String,
          lifts: r['lifts'] as int?,
          escalators: r['escalators'] as int?,
          tactilePath: b(r['tactile_path']),
          wheelchairAvailable: b(r['wheelchair_available']),
          notesEn: r['notes_en'] as String?,
          notesHi: r['notes_hi'] as String?,
          provenance: prov(r),
        ),
        'ORDER BY station_id',
      ),
      fareSlabs: rows(
        'fare_slab',
        (r) => FareSlab(
          fareSystemId: r['fare_system_id'] as String,
          dayType: DayType.parse(r['day_type'] as String),
          minKm: r['min_km'] as int,
          maxKm: r['max_km'] as int?,
          amountPaise: r['amount_paise'] as int,
        ),
        'ORDER BY fare_system_id, day_type, min_km',
      ),
      fareDiscounts: rows(
        'fare_discount',
        (r) => FareDiscount(
          fareSystemId: r['fare_system_id'] as String,
          media: FareMedia.parse(r['media'] as String),
          kind: FareDiscountKind.parse(r['kind'] as String),
          percent: r['percent'] as int,
          windowsJson: r['windows_json'] as String?,
        ),
        'ORDER BY fare_system_id, media, kind',
      ),
      fareOverrides: rows(
        'fare_override',
        (r) => FareOverride(
          fareSystemId: r['fare_system_id'] as String,
          fromStation: r['from_station'] as String,
          toStation: r['to_station'] as String,
          dayType: DayType.parse(r['day_type'] as String),
          amountPaise: r['amount_paise'] as int,
          sourceId: r['source_id'] as String,
          verifiedOn: r['verified_on'] as String,
        ),
        'ORDER BY fare_system_id, from_station, to_station, day_type',
      ),
      timings: rows(
        'timing',
        (r) => Timing(
          serviceId: r['service_id'] as String,
          stationId: r['station_id'] as String,
          directionTerminalId: r['direction_terminal_id'] as String,
          dayType: DayType.parse(r['day_type'] as String),
          firstDep: r['first_dep'] as int,
          lastDep: r['last_dep'] as int,
          provenance: prov(r),
        ),
        'ORDER BY service_id, station_id, direction_terminal_id, day_type',
      ),
      origins: rows(
        'origin',
        (r) => Origin(
          entity: r['entity'] as String,
          entityId: r['entity_id'] as String,
          field: r['field'] as String,
          sourceId: r['source_id'] as String,
          externalId: r['external_id'] as String?,
          status: OriginStatus.parse(r['status'] as String),
          detail: r['detail'] as String?,
        ),
        'ORDER BY entity, entity_id, field, source_id',
      ),
    );
  }
}
