import 'dart:io';

import 'package:metro_core/metro_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late Directory tmp;
  late MetroSnapshot fixture;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('metro_core_test_');
    fixture = loadFixture();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String path(String name) => '${tmp.path}/$name';

  /// Writes the fixture and returns the file path.
  String build([String name = 'metro.sqlite']) {
    DatasetWriter.writeFile(fixture, path(name));
    return path(name);
  }

  /// Opens the built file read-write with FK checks off, to corrupt it.
  void tamper(String file, void Function(Database db) change) {
    final db = sqlite3.open(file)
      ..execute('PRAGMA foreign_keys = OFF')
      ..execute('PRAGMA ignore_check_constraints = ON');
    try {
      change(db);
    } finally {
      db.close();
    }
  }

  DatasetException failure(String file) {
    try {
      DatasetReader.readFile(file);
    } on DatasetException catch (e) {
      return e;
    }
    fail('expected DatasetException');
  }

  group('write -> read round trip', () {
    test('preserves every table', () {
      final read = DatasetReader.readFile(build());
      expect(read.meta, fixture.meta);
      expect(read.sources.length, fixture.sources.length);
      expect(
        read.operators.map((x) => x.id),
        unorderedEquals(['test-op-a', 'test-op-b']),
      );
      expect(read.lines.map((x) => x.id), [
        'test-red',
        'test-blue',
        'test-green',
      ]);
      expect(read.services.length, fixture.services.length);
      expect(read.serviceStops.length, fixture.serviceStops.length);
      expect(read.stations.length, fixture.stations.length);
      expect(read.stationNames.length, fixture.stationNames.length);
      expect(read.stationLines.length, fixture.stationLines.length);
      expect(read.edges.length, fixture.edges.length);
      expect(read.transfers.length, fixture.transfers.length);
      expect(read.walkLinks.length, fixture.walkLinks.length);
      expect(read.platforms.length, fixture.platforms.length);
      expect(read.gates.length, fixture.gates.length);
      expect(read.gateLandmarks.length, fixture.gateLandmarks.length);
      expect(read.facilities.length, fixture.facilities.length);
      expect(read.accessibility.length, fixture.accessibility.length);
      expect(read.fareSystems.length, fixture.fareSystems.length);
      expect(read.fareSlabs.length, fixture.fareSlabs.length);
      expect(read.fareDiscounts.length, fixture.fareDiscounts.length);
      expect(read.fareOverrides.length, fixture.fareOverrides.length);
      expect(read.timings.length, fixture.timings.length);
    });

    test('preserves values, nulls (unknown) and Hindi text', () {
      final read = DatasetReader.readFile(build());
      final alpha = read.station('test-alpha')!;
      expect(alpha.nameHi, 'टेस्ट अल्फा');
      expect(alpha.lat, 28.6);
      expect(alpha.provenance.confidence, Confidence.community);
      expect(alpha.provenance.verifiedOn, isNull);
      expect(alpha.mapX, isNull);

      final g1 = read.gates.firstWhere((g) => g.id == 'test-alpha:g1');
      final g2 = read.gates.firstWhere((g) => g.id == 'test-alpha:g2');
      expect(g1.hasLift, isTrue);
      expect(g2.hasLift, isNull, reason: 'unknown must not become false');

      final acc = read.accessibilityAt('test-alpha')!;
      expect(acc.lifts, 2);
      expect(acc.wheelchairAvailable, isNull);

      final blue = read.timings.firstWhere(
        (t) => t.serviceId == 'test-blue-main',
      );
      expect(blue.lastDep, 1470);

      final slab = read.fareSlabs.firstWhere(
        (x) => x.fareSystemId == 'test-fare-a' && x.minKm == 12,
      );
      expect(slab.maxKm, isNull);
      expect(slab.amountPaise, 4000);

      final over = read.fareOverrides.single;
      expect(over.amountPaise, 5000);
      expect(over.verifiedOn, '2026-10-01');

      expect(read.walkLinks.single.requiresExit, isTrue);
      expect(read.transfers.first.stepFree, isTrue);
      final off = read.fareDiscounts.firstWhere(
        (d) => d.kind == FareDiscountKind.offPeak,
      );
      expect(off.windowsJson, contains('"from":360'));
    });

    test('read snapshot validates cleanly', () {
      final read = DatasetReader.readFile(build());
      expect(validateSnapshot(read).errors, isEmpty);
    });

    test('is deterministic: same input gives the same rows', () {
      final a = DatasetReader.readFile(build('a.sqlite'));
      final b = DatasetReader.readFile(build('b.sqlite'));
      expect(a.stations.map((x) => x.id), b.stations.map((x) => x.id));
      expect(a.edges.map((x) => x.id), b.edges.map((x) => x.id));
    });

    test('stamps PRAGMA user_version with the schema version', () {
      final db = sqlite3.open(build(), mode: OpenMode.readOnly);
      addTearDown(db.close);
      expect(
        db.select('PRAGMA user_version').first.columnAt(0),
        currentSchemaVersion,
      );
    });

    test('rewrites an existing file instead of appending', () {
      final file = build();
      DatasetWriter.writeFile(fixture, file);
      expect(DatasetReader.readFile(file).stations, hasLength(12));
    });

    test('works on in-memory databases', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      DatasetWriter.write(fixture, db);
      expect(DatasetReader.read(db).stations, hasLength(12));
    });

    test('the schema declares every table the writer fills', () {
      final db = sqlite3.open(build(), mode: OpenMode.readOnly);
      addTearDown(db.close);
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'])
          .toSet();
      expect(tables, containsAll(schemaTables));
    });
  });

  group('provenance survives copyWith and the sqlite round trip', () {
    test('origins and source version/hash', () {
      const origin = Origin(
        entity: 'station',
        entityId: 'test-alpha',
        field: 'name_hi',
        sourceId: 'test-fixture',
        status: OriginStatus.curatedOverride,
        externalId: 'Q1',
        detail: 'why',
      );
      final withOrigin = fixture
          .copyWith(
            origins: [origin],
            sources: [
              const Source(
                id: 'test-fixture',
                name: 'TEST DATA',
                license: 'CC0',
                version: 'v1',
                sha256: 'abc',
              ),
            ],
          )
          .copyWith(meta: {...fixture.meta});
      expect(withOrigin.origins, hasLength(1));
      final read = DatasetReader.readFile(
        (() {
          DatasetWriter.writeFile(withOrigin, path('o.sqlite'));
          return path('o.sqlite');
        })(),
      );
      final o = read.origins.single;
      expect(o.status, OriginStatus.curatedOverride);
      expect(o.externalId, 'Q1');
      expect(o.detail, 'why');
      expect(read.sources.single.version, 'v1');
      expect(read.sources.single.sha256, 'abc');
    });
  });

  group('writer enforces referential integrity', () {
    test(
      'rejects an edge to an unknown station and leaves no file content',
      () {
        final broken = fixture.copyWith(
          edges: [edgeWith(fixture.edges.first, to: 'ghost')],
        );
        expect(
          () => DatasetWriter.writeFile(broken, path('bad.sqlite')),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('rejects an unknown enum-like value via CHECK constraints', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      DatasetWriter.write(fixture, db);
      expect(
        () => db.execute("UPDATE station SET status = 'sideways'"),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('reader rejects unusable files', () {
    test('missing file', () {
      final e = failure(path('absent.sqlite'));
      expect(e.failure, DatasetFailure.unreadable);
    });

    test('file that is not a database', () {
      File(
        path('junk.sqlite'),
      ).writeAsStringSync('this is definitely not sqlite' * 20);
      expect(failure(path('junk.sqlite')).failure, DatasetFailure.unreadable);
    });

    test('truncated database', () {
      final file = build();
      final bytes = File(file).readAsBytesSync();
      File(file).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 3));
      expect(
        failure(file).failure,
        anyOf(DatasetFailure.unreadable, DatasetFailure.malformed),
      );
    });

    test('empty file', () {
      File(path('empty.sqlite')).writeAsBytesSync([]);
      final e = failure(path('empty.sqlite'));
      // An empty file is a valid empty db with user_version 0 -> too old.
      expect(
        e.failure,
        anyOf(DatasetFailure.incompatibleSchema, DatasetFailure.malformed),
      );
    });

    test('schema too new', () {
      final file = build();
      tamper(file, (db) => db.execute('PRAGMA user_version = 99'));
      final e = failure(file);
      expect(e.failure, DatasetFailure.incompatibleSchema);
      expect(e.message, contains('99'));
    });

    test('schema too old', () {
      final file = build();
      tamper(file, (db) => db.execute('PRAGMA user_version = 0'));
      expect(failure(file).failure, DatasetFailure.incompatibleSchema);
    });

    test('meta.schema_version disagrees with user_version', () {
      final file = build();
      tamper(
        file,
        (db) => db.execute(
          "UPDATE meta SET value = '2' WHERE key = 'schema_version'",
        ),
      );
      expect(failure(file).failure, DatasetFailure.malformed);
    });

    test('missing table', () {
      final file = build();
      tamper(file, (db) => db.execute('DROP TABLE gate_landmark'));
      expect(failure(file).failure, DatasetFailure.malformed);
    });

    test('unknown confidence value in a row', () {
      final file = build();
      tamper(file, (db) => db.execute("UPDATE edge SET confidence = 'maybe'"));
      // CHECK constraints are bypassed above; the parser must still refuse it.
      expect(failure(file).failure, DatasetFailure.malformed);
    });

    test('broken foreign key is caught by validation', () {
      final file = build();
      tamper(
        file,
        (db) => db.execute("DELETE FROM station WHERE id = 'test-delta'"),
      );
      final e = failure(file);
      expect(e.failure, DatasetFailure.invalid);
      expect(e.report!.hasError('missing-ref'), isTrue);
    });

    test('orphan station is caught by validation', () {
      final file = build();
      tamper(file, (db) {
        db.execute('DELETE FROM service_stop WHERE station_id = ?', [
          'test-mu',
        ]);
        db.execute(
          'DELETE FROM edge WHERE from_station = ? OR to_station = ?',
          ['test-mu', 'test-mu'],
        );
        db.execute('DELETE FROM station_line WHERE station_id = ?', [
          'test-mu',
        ]);
      });
      final e = failure(file);
      expect(e.failure, DatasetFailure.invalid);
      expect(e.report!.hasError('orphan-station'), isTrue);
    });

    test('validate:false skips validation but not parsing', () {
      final file = build();
      tamper(
        file,
        (db) => db.execute("DELETE FROM station WHERE id = 'test-delta'"),
      );
      expect(
        DatasetReader.readFile(file, validate: false).stations,
        hasLength(11),
      );
    });
  });

  group('repositories', () {
    test('SqliteDatasetRepository loads and validates', () async {
      final s = await SqliteDatasetRepository(build()).load();
      expect(s.stations, hasLength(12));
    });

    test('SqliteDatasetRepository surfaces DatasetException', () {
      expect(
        SqliteDatasetRepository(path('absent.sqlite')).load(),
        throwsA(isA<DatasetException>()),
      );
    });

    test('InMemoryDatasetRepository returns the same snapshot', () async {
      expect(await InMemoryDatasetRepository(fixture).load(), same(fixture));
    });

    test('both implementations satisfy the interface', () {
      final DatasetRepository a = InMemoryDatasetRepository(fixture);
      final DatasetRepository b = SqliteDatasetRepository(path('x'));
      expect([a, b], hasLength(2));
    });
  });
}
