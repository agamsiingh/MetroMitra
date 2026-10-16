import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/update_providers.dart';
import 'package:metromitra/shared/data/updater/dataset_updater.dart';
import 'package:metromitra/shared/data/updater/update_transport.dart';
import 'package:sqlite3/sqlite3.dart';

import 'update_rig.dart';

void main() {
  late UpdateRig rig;
  late File bundled;

  setUp(() async {
    rig = await UpdateRig.create(bundledVersion: '2026.10.0');
    bundled = writeDataset('${rig.dir.path}/bundled.sqlite', '2026.10.0');
  });
  tearDown(() => rig.dispose());

  /// Active dataset is unchanged and still loads.
  Future<void> expectStill(String version, {String? label}) async {
    final r = await rig.launch(bundled: bundled);
    expect(versionOf(r), version);
    if (label != null) expect(labelOf(r), label);
  }

  group('integration: the full flow', () {
    test(
      'bundled -> valid update -> active changes; corrupted -> stays',
      () async {
        // 1. only the bundled dataset
        await expectStill('2026.10.0', label: 'bundled');

        // 2. a valid (gzipped) update is installed and becomes active
        await rig.publish('2026.10.1', gz: true);
        final ok = await rig.updater.run();
        expect(ok.status, UpdateStatus.installed, reason: ok.detail);
        expect(rig.store.read().active, '2026.10.1');
        await expectStill('2026.10.1', label: 'updated 2026.10.1');

        // 3. a second update: the first becomes the fallback
        await rig.publish('2026.10.2');
        expect((await rig.updater.run()).installed, isTrue);
        final p = rig.store.read();
        expect((p.active, p.previous), ('2026.10.2', '2026.10.1'));
        await expectStill('2026.10.2');

        // 4. corrupted bytes on the wire: checksum fails, nothing changes
        await rig.publish(
          '2026.10.3',
          corruptServed: (b) => [...b]..[b.length ~/ 2] ^= 0xff,
        );
        final bad = await rig.updater.run();
        expect(bad.status, UpdateStatus.checksum);
        expect(rig.store.read().active, '2026.10.2');
        await expectStill('2026.10.2', label: 'updated 2026.10.2');

        // 5. correct checksum + signature, but not a usable dataset
        final broken = writeDataset(
          '${rig.dir.path}/broken.sqlite',
          '2026.10.4',
        );
        final db = sqlite3.open(broken.path);
        db.execute('PRAGMA foreign_keys = OFF');
        db.execute('DELETE FROM station_line');
        db.close();
        await rig.publish('2026.10.4', source: broken);
        final invalid = await rig.updater.run();
        expect(invalid.status, UpdateStatus.datasetInvalid);
        expect(rig.store.read().active, '2026.10.2');
        await expectStill('2026.10.2');

        // 6. nothing half-installed is left behind
        final dirs = rig.store.root
            .listSync()
            .whereType<Directory>()
            .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
            .toSet();
        expect(dirs, {'2026.10.1', '2026.10.2', '.staging'});
        expect(
          rig.store.stagingDir.listSync().whereType<Directory>(),
          isEmpty,
          reason: 'attempt folders are removed',
        );
      },
    );
  });

  group('rejected updates keep the active dataset', () {
    test('invalid signature (tampered after signing)', () async {
      await rig.publish('2026.10.1', afterSign: (m) => m['size'] = 5);
      final r = await rig.updater.run();
      expect(r.status, UpdateStatus.untrusted);
      expect(rig.server.requests, ['/manifest.json'], reason: 'no download');
      await expectStill('2026.10.0');
    });

    test('signed by a key the app does not trust', () async {
      await rig.publish('2026.10.1', seed: otherSeed);
      expect((await rig.updater.run()).status, UpdateStatus.untrusted);
      expect(rig.store.read().active, isNull);
    });

    test('bad checksum (signed sha256 is not the file)', () async {
      await rig.publish('2026.10.1', tweak: (m) => m['sha256'] = '0' * 64);
      final r = await rig.updater.run();
      expect(r.status, UpdateStatus.checksum);
      expect(rig.store.read().active, isNull);
      expect(
        rig.store.stagingDir.listSync().whereType<File>(),
        isEmpty,
        reason: 'the bad download is deleted',
      );
    });

    test('file larger than signed size (also a gzip bomb)', () async {
      await rig.publish('2026.10.1', gz: true, tweak: (m) => m['size'] = 100);
      expect((await rig.updater.run()).status, UpdateStatus.checksum);
    });

    test('truncated gzip', () async {
      await rig.publish(
        '2026.10.1',
        gz: true,
        corruptServed: (b) => b.sublist(0, b.length ~/ 2),
      );
      final r = await rig.updater.run();
      expect(r.status, anyOf(UpdateStatus.checksum, UpdateStatus.network));
      expect(rig.store.read().active, isNull);
    });

    test('malformed manifests', () async {
      for (final text in [
        '',
        'not json',
        '[]',
        '{}',
        jsonEncode({'dataset_version': '../../x'}),
      ]) {
        rig.server.files['/manifest.json'] = utf8.encode(text);
        expect((await rig.updater.run()).status, UpdateStatus.manifestInvalid);
      }
    });

    test('manifest with a path-like version is refused', () async {
      await rig.publish(
        '2026.10.1',
        tweak: (m) => m['dataset_version'] = '../evil',
      );
      expect((await rig.updater.run()).status, UpdateStatus.manifestInvalid);
    });

    test('schema newer than the app: skipped before downloading', () async {
      await rig.publish(
        '2026.10.1',
        tweak: (m) => m['schema_version'] = currentSchemaVersion + 1,
      );
      final r = await rig.updater.run();
      expect(r.status, UpdateStatus.schemaTooNew);
      expect(rig.server.requests, ['/manifest.json']);
    });

    test(
      'file whose schema is newer than the app: invalid, not installed',
      () async {
        final f = writeDataset('${rig.dir.path}/future.sqlite', '2026.10.1');
        final db = sqlite3.open(f.path)..execute('PRAGMA user_version = 99');
        db.close();
        await rig.publish('2026.10.1', source: f);
        expect((await rig.updater.run()).status, UpdateStatus.datasetInvalid);
        await expectStill('2026.10.0');
      },
    );

    test('manifest lies about the dataset version', () async {
      final f = writeDataset('${rig.dir.path}/v.sqlite', '2026.10.1');
      await rig.publish('2026.10.9', source: f); // file says .1, manifest .9
      expect((await rig.updater.run()).status, UpdateStatus.datasetInvalid);
      expect(rig.store.read().active, isNull);
    });

    test('not a SQLite file at all', () async {
      final f = File('${rig.dir.path}/junk.sqlite')
        ..writeAsBytesSync(List.filled(4096, 7));
      await rig.publish('2026.10.1', source: f);
      expect((await rig.updater.run()).status, UpdateStatus.datasetInvalid);
      expect(rig.store.read().active, isNull);
    });

    test('needs a newer app', () async {
      await rig.publish(
        '2026.10.1',
        tweak: (m) => m['min_app_version'] = '9.0.0',
      );
      expect((await rig.updater.run()).status, UpdateStatus.needsNewerApp);
    });

    test('draft datasets are refused in a strict build', () async {
      await rig.publish('2026.10.1', tweak: (m) => m['stage'] = 'draft');
      expect((await rig.updater.run()).status, UpdateStatus.notRelease);
    });

    test('a release manifest cannot carry a draft dataset', () async {
      final snap = YamlDatasetLoader.loadFile(fixturePath);
      final f = File('${rig.dir.path}/draft.sqlite');
      DatasetWriter.writeFile(
        snap.copyWith(
          meta: {
            ...snap.meta,
            'dataset_version': '2026.10.1',
            'stage': 'draft',
          },
        ),
        f.path,
      );
      await rig.publish('2026.10.1', source: f);
      expect((await rig.updater.run()).status, UpdateStatus.datasetInvalid);
    });
  });

  group('version handling', () {
    test('same version: nothing downloaded', () async {
      await rig.publish('2026.10.0');
      final r = await rig.updater.run();
      expect(r.status, UpdateStatus.upToDate);
      expect(rig.server.requests, ['/manifest.json']);
    });

    test('older version is never installed (no downgrade)', () async {
      await rig.publish('2026.9.9');
      expect((await rig.updater.run()).status, UpdateStatus.older);
      await rig.publish('2026.10.2');
      expect((await rig.updater.run()).installed, isTrue);
      await rig.publish('2026.10.1');
      expect((await rig.updater.run()).status, UpdateStatus.older);
      expect(rig.store.read().active, '2026.10.2');
    });

    test('newer version compares numerically, not as text', () async {
      expect(compareDottedVersions('2026.10.0', '2026.9.0'), greaterThan(0));
      expect(compareDottedVersions('2026.10', '2026.10.0'), 0);
      await rig.publish('2026.10.10');
      expect((await rig.updater.run()).installed, isTrue);
      await rig.publish('2026.10.9');
      expect((await rig.updater.run()).status, UpdateStatus.older);
    });

    test('a version marked bad is not installed again', () async {
      await rig.publish('2026.10.1');
      expect((await rig.updater.run()).installed, isTrue);
      rig.store.markBad('2026.10.1');
      expect(rig.store.read().active, isNull);
      expect((await rig.updater.run()).status, UpdateStatus.knownBad);
    });
  });

  group('network trouble', () {
    test('no network at all (nothing listening)', () async {
      final dead = await TestServer.start();
      final url = dead.url('/manifest.json');
      await dead.close();
      final u = DatasetUpdater(
        store: rig.store,
        transport: HttpUpdateTransport(
          allowInsecureLoopback: true,
          connectTimeout: const Duration(seconds: 1),
        ),
        verifier: ManifestVerifier([await keyFor(testSeed)]),
        appVersion: '0.1.0',
        manifestUrl: url,
      );
      expect((await u.run()).status, UpdateStatus.network);
      await expectStill('2026.10.0');
    });

    test('server error and missing files', () async {
      expect((await rig.updater.run()).status, UpdateStatus.network); // 404
      rig.server.status['/manifest.json'] = 503;
      expect((await rig.updater.run()).status, UpdateStatus.network);
    });

    test('a server that never answers times out', () async {
      final slow = await UpdateRig.create(
        idle: const Duration(milliseconds: 300),
      );
      addTearDown(slow.dispose);
      slow.server.hang.add('/manifest.json');
      final r = await slow.updater.run();
      expect(r.status, UpdateStatus.network);
      expect(r.detail, contains('timed out'));
    });

    test('plain http is refused outside tests', () async {
      final u = DatasetUpdater(
        store: rig.store,
        transport: HttpUpdateTransport(),
        verifier: ManifestVerifier([await keyFor(testSeed)]),
        appVersion: '0.1.0',
        manifestUrl: rig.server.url('/manifest.json'),
      );
      final r = await u.run();
      expect(r.status, UpdateStatus.network);
      expect(r.detail, contains('non-HTTPS'));
      expect(rig.server.requests, isEmpty);
    });

    test('interrupted download keeps the partial file and resumes', () async {
      await rig.publish('2026.10.1');
      final total = rig.server.files['/2026.10.1.sqlite']!.length;
      rig.server.cutAfter['/2026.10.1.sqlite'] = total ~/ 3;
      final first = await rig.updater.run();
      expect(first.status, UpdateStatus.network);
      expect(rig.store.read().active, isNull);
      final parts = rig.store.stagingDir.listSync().whereType<File>().toList();
      expect(parts, hasLength(1));
      expect(parts.single.lengthSync(), lessThan(total));
      await expectStill('2026.10.0');

      final second = await rig.updater.run();
      expect(second.status, UpdateStatus.installed, reason: second.detail);
      expect(rig.server.rangeHeaders, hasLength(1), reason: 'resumed');
      expect(rig.server.rangeHeaders.single, startsWith('bytes='));
      await expectStill('2026.10.1');
      expect(
        rig.store.stagingDir.listSync().whereType<File>(),
        isEmpty,
        reason: 'the part file is gone after success',
      );
    });

    test('a damaged partial file does not poison the retry', () async {
      await rig.publish('2026.10.1');
      rig.server.cutAfter['/2026.10.1.sqlite'] = 1000;
      await rig.updater.run();
      final part = rig.store.stagingDir.listSync().whereType<File>().single;
      part.writeAsBytesSync(List.filled(1000, 1)); // garbage prefix
      expect((await rig.updater.run()).status, UpdateStatus.checksum);
      expect(rig.store.stagingDir.listSync().whereType<File>(), isEmpty);
      expect(
        (await rig.updater.run()).installed,
        isTrue,
        reason: 'fresh start',
      );
    });
  });

  group('atomic install and rollback', () {
    test('a failing pointer write rolls the install back', () async {
      await rig.publish('2026.10.1');
      expect((await rig.updater.run()).installed, isTrue);
      // block the pointer's temp file: writing it fails mid-install
      Directory('${rig.store.root.path}/current.json.tmp').createSync();
      await rig.publish('2026.10.2');
      final r = await rig.updater.run();
      expect(r.status, UpdateStatus.installFailed);
      expect(rig.store.read().active, '2026.10.1');
      expect(
        Directory('${rig.store.root.path}/2026.10.2').existsSync(),
        isFalse,
        reason: 'the half-installed folder is removed',
      );
      await expectStill('2026.10.1', label: 'updated 2026.10.1');
    });

    test(
      'installed dataset that fails at launch falls back, then bundled',
      () async {
        await rig.publish('2026.10.1');
        await rig.updater.run();
        await rig.publish('2026.10.2');
        await rig.updater.run();
        // damage the active file on disk
        File(rig.store.pathOf('2026.10.2')).writeAsBytesSync([1, 2, 3]);
        var r = await rig.launch(bundled: bundled);
        expect(labelOf(r), 'previous 2026.10.1');
        rig.store.markBad('2026.10.2');
        expect(rig.store.read().active, '2026.10.1');
        // and the previous one too
        File(rig.store.pathOf('2026.10.1')).writeAsBytesSync([1, 2, 3]);
        r = await rig.launch(bundled: bundled);
        expect(labelOf(r), 'bundled');
        expect(versionOf(r), '2026.10.0');
      },
    );

    test('old datasets are pruned: only active and previous stay', () async {
      for (final v in ['2026.10.1', '2026.10.2', '2026.10.3']) {
        await rig.publish(v);
        expect((await rig.updater.run()).installed, isTrue);
      }
      final names = rig.store.root
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toSet();
      expect(names, {'2026.10.2', '2026.10.3', '.staging'});
    });

    test(
      'a damaged or hostile current.json is ignored, never followed',
      () async {
        rig.store.root.createSync(recursive: true);
        for (final text in [
          'garbage',
          '[]',
          jsonEncode({'active': '../../etc', 'previous': 'a/b'}),
        ]) {
          File('${rig.store.root.path}/current.json').writeAsStringSync(text);
          expect(rig.store.read().active, isNull);
          expect(rig.store.candidates(), isEmpty);
        }
        await expectStill('2026.10.0', label: 'bundled');
      },
    );

    test('an update never overwrites a dataset that is in use', () {
      final f = writeDataset('${rig.dir.path}/x.sqlite', '2026.10.1');
      rig.store.install(f, '2026.10.1');
      final g = writeDataset('${rig.dir.path}/y.sqlite', '2026.10.1');
      expect(() => rig.store.install(g, '2026.10.1'), throwsStateError);
      expect(rig.store.read().active, '2026.10.1');
    });
  });

  group('configuration and schedule', () {
    test('no key or no address: disabled, no network', () async {
      final u = DatasetUpdater(
        store: rig.store,
        transport: HttpUpdateTransport(allowInsecureLoopback: true),
        verifier: const ManifestVerifier([]),
        appVersion: '0.1.0',
        manifestUrl: rig.server.url('/manifest.json'),
      );
      expect(u.enabled, isFalse);
      expect((await u.run()).status, UpdateStatus.disabled);
      expect(rig.server.requests, isEmpty);
    });

    test('the build embeds no key yet, so it can install nothing', () {
      expect(trustedPublicKeys, isEmpty);
    });

    test('at most one check per 24 hours', () {
      final t = DateTime.utc(2026, 10, 8, 12);
      expect(updateIsDue(null, t), isTrue);
      expect(updateIsDue(t, t.add(const Duration(hours: 23))), isFalse);
      expect(updateIsDue(t, t.add(const Duration(hours: 24))), isTrue);
      expect(updateIsDue(t, t.subtract(const Duration(hours: 1))), isTrue);
      rig.store.recordCheck(t);
      expect(rig.store.lastCheck, t);
    });

    test('app version constant matches pubspec', () {
      final v = RegExp(
        r'^version:\s*([\d.]+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
      expect(appVersion, v);
    });
  });
}
