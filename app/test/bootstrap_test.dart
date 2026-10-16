import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';
import 'package:metromitra/bootstrap/metro_services.dart';

const _fixture = '../data/fixtures/mini_network/dataset.yaml';

void main() {
  late Directory tmp;
  late MetroSnapshot fixture;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bootstrap_test_');
    fixture = YamlDatasetLoader.loadFile(_fixture);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(MetroSnapshot s, [String name = 'metro.sqlite']) {
    final path = '${tmp.path}/$name';
    DatasetWriter.writeFile(s, path);
    return path;
  }

  MetroSnapshot asRelease(MetroSnapshot s) => s.copyWith(
    meta: {
      for (final e in s.meta.entries)
        if (e.key != MetaKeys.isTestData) e.key: e.value,
    },
  );

  MetroSnapshot asDraft(MetroSnapshot s) => asRelease(
    s,
  ).copyWith(meta: {...asRelease(s).meta, MetaKeys.stage: 'draft'});

  DatasetCandidate cand(String path, [String label = 'c']) =>
      DatasetCandidate(label: label, path: path);

  const testOk = DatasetPolicy(allowTestData: true);

  group('loading', () {
    test('a valid release dataset loads and is exposed intact', () async {
      final path = write(asRelease(fixture));
      final r = await bootstrapDataset(candidates: [cand(path)]);
      expect(r, isA<BootstrapReady>());
      final ready = r as BootstrapReady;
      expect(ready.snapshot.stations, hasLength(fixture.stations.length));
      expect(ready.snapshot.datasetVersion, fixture.datasetVersion);
      expect(ready.sourceLabel, 'c');
      expect(ready.skipped, isEmpty);
    });

    test('services (search + routing) are built from the snapshot', () async {
      final path = write(asRelease(fixture));
      final ready =
          await bootstrapDataset(candidates: [cand(path)]) as BootstrapReady;
      final services = MetroServices(ready.snapshot);
      expect(services.search.search('TEST Alpha').first.entityId, 'test-alpha');
      expect(services.planner.plan('test-alpha', 'test-zeta').isOk, isTrue);
      expect(services.isDraft, isFalse);
    });

    test('is deterministic: same file, same result', () async {
      final path = write(asRelease(fixture));
      final a =
          await bootstrapDataset(candidates: [cand(path)]) as BootstrapReady;
      final b =
          await bootstrapDataset(candidates: [cand(path)]) as BootstrapReady;
      expect(
        a.snapshot.stations.map((s) => s.id).toList(),
        b.snapshot.stations.map((s) => s.id).toList(),
      );
      expect(a.snapshot.meta, b.snapshot.meta);
    });

    test('loads off the UI isolate with the production loader', () async {
      final path = write(asRelease(fixture));
      final r = await bootstrapDataset(
        candidates: [cand(path)],
        loader: loadDatasetInIsolate,
      );
      expect(r, isA<BootstrapReady>());
    });

    test('a failure inside the isolate is reported, not thrown', () async {
      final junk = File('${tmp.path}/junk.sqlite')
        ..writeAsBytesSync(Uint8List(200)..fillRange(0, 200, 7));
      final r = await bootstrapDataset(
        candidates: [cand(junk.path)],
        loader: loadDatasetInIsolate,
      );
      expect((r as BootstrapFailed).problem, DatasetProblem.corrupt);
    });
  });

  group('missing, corrupt and incompatible datasets', () {
    test('no candidates -> missing', () async {
      final r = await bootstrapDataset(candidates: const []);
      expect(r, isA<BootstrapFailed>());
      expect((r as BootstrapFailed).problem, DatasetProblem.missing);
      expect(r.attempts, isEmpty);
    });

    test('candidate file does not exist -> missing', () async {
      final r = await bootstrapDataset(
        candidates: [cand('${tmp.path}/nope.sqlite')],
      );
      expect((r as BootstrapFailed).problem, DatasetProblem.missing);
    });

    test('garbage bytes -> corrupt', () async {
      final f = File('${tmp.path}/g.sqlite')
        ..writeAsBytesSync(List.generate(500, (i) => i % 251));
      final r = await bootstrapDataset(candidates: [cand(f.path)]);
      expect((r as BootstrapFailed).problem, DatasetProblem.corrupt);
    });

    test('empty file -> not usable', () async {
      final f = File('${tmp.path}/e.sqlite')..writeAsBytesSync([]);
      final r = await bootstrapDataset(candidates: [cand(f.path)]);
      expect(
        (r as BootstrapFailed).problem,
        anyOf(DatasetProblem.corrupt, DatasetProblem.incompatible),
      );
    });

    test('truncated file -> a problem, never a crash', () async {
      final path = write(asRelease(fixture));
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 3));
      final r = await bootstrapDataset(candidates: [cand(path)]);
      expect(r, isA<BootstrapFailed>());
      expect((r as BootstrapFailed).problem, isNot(DatasetProblem.missing));
    });

    test('schema from a newer app -> incompatible', () async {
      final path = write(asRelease(fixture));
      final bytes = File(path).readAsBytesSync();
      // SQLite header: user_version is the big-endian int at offset 60.
      ByteData.sublistView(bytes).setUint32(60, 99);
      File(path).writeAsBytesSync(bytes);
      final r = await bootstrapDataset(candidates: [cand(path)]);
      expect((r as BootstrapFailed).problem, DatasetProblem.incompatible);
      expect(r.attempts.single.detail, contains('99'));
    });

    test('a dataset that breaks the validation rules -> invalid', () async {
      final broken = asRelease(fixture).copyWith(
        stations: [
          for (final s in fixture.stations)
            Station(
              id: s.id,
              nameEn: s.nameEn,
              nameHi: s.nameHi,
              lat: 0,
              lng: 0,
              status: s.status,
              provenance: s.provenance,
            ),
        ],
      );
      final path = write(broken);
      final r = await bootstrapDataset(candidates: [cand(path)]);
      expect((r as BootstrapFailed).problem, DatasetProblem.invalid);
    });
  });

  group('policy: draft and test data', () {
    test('test data is refused unless the build allows it', () async {
      final path = write(fixture);
      final strict = await bootstrapDataset(candidates: [cand(path)]);
      expect(
        (strict as BootstrapFailed).problem,
        DatasetProblem.testDataNotAllowed,
      );
      final ok = await bootstrapDataset(
        candidates: [cand(path)],
        policy: testOk,
      );
      expect(ok, isA<BootstrapReady>());
    });

    test('a draft dataset is refused in a strict build', () async {
      final path = write(asDraft(fixture));
      final r = await bootstrapDataset(candidates: [cand(path)]);
      expect((r as BootstrapFailed).problem, DatasetProblem.draftNotAllowed);
    });

    test('a draft loads when drafts are allowed, and says so', () async {
      final path = write(asDraft(fixture));
      final r =
          await bootstrapDataset(
                candidates: [cand(path)],
                policy: const DatasetPolicy(allowDraft: true),
              )
              as BootstrapReady;
      expect(r.snapshot.isDraft, isTrue);
      expect(MetroServices(r.snapshot).isDraft, isTrue);
    });

    test('allowing drafts still accepts a release dataset', () async {
      final path = write(asRelease(fixture));
      final r = await bootstrapDataset(
        candidates: [cand(path)],
        policy: const DatasetPolicy(allowDraft: true),
      );
      expect(r, isA<BootstrapReady>());
    });

    test('release mode ignores the developer switches', () {
      final p = DatasetPolicy.fromEnvironment(isReleaseMode: true);
      expect(p.allowDraft, isFalse);
      expect(p.allowTestData, isFalse);
    });
  });

  group('candidate order and fallback', () {
    test('a bad first candidate falls back to the next good one', () async {
      final bad = File('${tmp.path}/bad.sqlite')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final good = write(asRelease(fixture), 'good.sqlite');
      final r =
          await bootstrapDataset(
                candidates: [cand(bad.path, 'updated'), cand(good, 'bundled')],
              )
              as BootstrapReady;
      expect(r.sourceLabel, 'bundled');
      expect(r.skipped.single.label, 'updated');
      expect(r.skipped.single.problem, DatasetProblem.corrupt);
    });

    test('the first good candidate wins; later ones are not used', () async {
      final a = write(asRelease(fixture), 'a.sqlite');
      final b = File('${tmp.path}/b.sqlite')..writeAsBytesSync([9, 9]);
      final r =
          await bootstrapDataset(
                candidates: [cand(a, 'first'), cand(b.path, 'second')],
              )
              as BootstrapReady;
      expect(r.sourceLabel, 'first');
    });

    test(
      'all bad: first problem is reported, every attempt is listed',
      () async {
        final bad = File('${tmp.path}/bad.sqlite')
          ..writeAsBytesSync([1, 2, 3, 4]);
        final r =
            await bootstrapDataset(
                  candidates: [
                    cand('${tmp.path}/none.sqlite', 'a'),
                    cand(bad.path, 'b'),
                  ],
                )
                as BootstrapFailed;
        expect(r.problem, DatasetProblem.missing);
        expect(r.attempts.map((a) => a.label), ['a', 'b']);
        expect(r.attempts.map((a) => a.problem), [
          DatasetProblem.missing,
          DatasetProblem.corrupt,
        ]);
      },
    );

    test('a loader that throws something unexpected is contained', () async {
      final path = write(asRelease(fixture));
      final r = await bootstrapDataset(
        candidates: [cand(path)],
        loader: (p, m) => throw StateError('boom'),
      );
      expect((r as BootstrapFailed).problem, DatasetProblem.corrupt);
    });
  });
}
