import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/data_pipeline.dart';
import 'package:test/test.dart';

import 'support/support.dart';

const _osmUrl = 'https://overpass.test/api/interpreter';
const _statusUrl = 'https://overpass.test/api/status';
const _wdUrl = 'https://sparql.test/sparql';

void main() {
  late Directory tmp;
  late PipelineConfig cfg;
  late RawCache cache;
  late List<Duration> sleeps;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fetch_test_');
    cfg = testConfig();
    cache = RawCache(
      '${tmp.path}/cache',
      '${tmp.path}/cache/sources.lock.json',
    );
    sleeps = [];
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  final osm = MiniOsm.bytes();
  final wd = MiniWd.bytes();

  Fetcher fetcher(FakeTransport t, {PipelineConfig? config}) => Fetcher(
    transport: t,
    settings: (config ?? cfg).fetch,
    userAgent: 'TestAgent/1.0',
    now: () => DateTime.utc(2026, 10, 5, 12),
    sleep: (d) async => sleeps.add(d),
  );

  FakeTransport happy() => FakeTransport({
    _statusUrl: [overpassStatus()],
    _osmUrl: [ok(osm)],
    _wdUrl: [ok(wd)],
  });

  Future<SourceLock> fetch(
    FakeTransport t, {
    bool acceptShrink = false,
    PipelineConfig? config,
  }) => fetcher(t, config: config).fetchAll(
    config ?? cfg,
    cache: cache,
    acceptShrink: acceptShrink,
  );

  List<String> cacheFiles() => Directory(cache.dir).existsSync()
      ? (Directory(
            cache.dir,
          ).listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last).toList()
          ..sort())
      : [];

  group('successful fetch', () {
    test('writes content-addressed cache files and a lock', () async {
      final lock = await fetch(happy());
      final osmEntry = lock[osmSourceId]!;
      expect(osmEntry.sha256, sha256Hex(osm));
      expect(osmEntry.bytes, osm.length);
      expect(osmEntry.records, 16);
      expect(osmEntry.retrievedAt, '2026-10-05T12:00:00Z');
      expect(osmEntry.sourceVersion, '2026-10-05T00:00:00Z');
      expect(osmEntry.file, startsWith('osm-overpass.'));
      expect(File('${cache.dir}/${osmEntry.file}').readAsBytesSync(), osm);
      expect(cache.readLock()[wikidataSourceId]!.records, 2);
      // the lock round-trips and verifies the cached bytes
      expect(cache.read(cache.readLock()[osmSourceId]!), osm);
    });

    test('lock records licence, endpoint and the query hash', () async {
      final lock = await fetch(happy());
      expect(lock[osmSourceId]!.license, 'ODbL-1.0');
      expect(lock[osmSourceId]!.endpoint, _osmUrl);
      expect(
        lock[osmSourceId]!.requestSha256,
        sha256Hex(utf8.encode(cfg.remoteById(osmSourceId).query)),
      );
    });

    test('identifies itself and posts the query form-encoded', () async {
      final t = happy();
      await fetch(t);
      final post = t.requests.firstWhere(
        (r) => r.method == 'POST' && r.url.toString() == _osmUrl,
      );
      expect(post.headers['User-Agent'], 'TestAgent/1.0');
      expect(post.body, startsWith('data='));
      expect(
        Uri.decodeQueryComponent(post.body!.substring(5)),
        contains('test-osm-query'),
      );
      final wdReq = t.requests.firstWhere((r) => r.url.toString() == _wdUrl);
      expect(wdReq.headers['Accept'], contains('sparql-results+json'));
      expect(wdReq.body, startsWith('query='));
    });

    test(
      'is sequential: Overpass status check, Overpass, then Wikidata',
      () async {
        final t = happy();
        await fetch(t);
        expect(t.requests.map((r) => r.url.toString()).toList(), [
          _statusUrl,
          _osmUrl,
          _wdUrl,
        ]);
      },
    );

    test('lock file is canonical (stable bytes)', () async {
      await fetch(happy());
      final first = File(cache.lockPath).readAsStringSync();
      expect(first.endsWith('\n'), isTrue);
      expect(
        first.indexOf('"osm-overpass"'),
        lessThan(first.indexOf('"wikidata"')),
      );
      expect(SourceLock.decode(first).encode(), first);
    });

    test(
      'a new fetch keeps previous file until the lock is committed, then removes it',
      () async {
        await fetch(happy());
        final before = cacheFiles();
        final osm2 = MiniOsm.bytes(northHindi: true);
        await fetch(
          FakeTransport({
            _statusUrl: [overpassStatus()],
            _osmUrl: [ok(osm2)],
            _wdUrl: [ok(wd)],
          }),
        );
        final after = cacheFiles();
        expect(after.where((f) => f.startsWith('osm-overpass.')), hasLength(1));
        expect(after, isNot(equals(before)));
        expect(cache.read(cache.readLock()[osmSourceId]!), osm2);
      },
    );
  });

  group('safe failure: network', () {
    test('retries 504 with exponential backoff and then succeeds', () async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [status(504), status(504), ok(osm)],
        _wdUrl: [ok(wd)],
      });
      await fetch(t);
      expect(sleeps, [
        const Duration(seconds: 30),
        const Duration(seconds: 60),
      ]);
      expect(cache.readLock()[osmSourceId], isNotNull);
    });

    test('honours Retry-After when longer than the backoff', () async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [
          status(429, {'retry-after': '100'}),
          ok(osm),
        ],
        _wdUrl: [ok(wd)],
      });
      await fetch(t);
      expect(sleeps.first, const Duration(seconds: 100));
    });

    test('retries socket errors', () async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [const SocketException('network down'), ok(osm)],
        _wdUrl: [ok(wd)],
      });
      await fetch(t);
      expect(cache.readLock()[osmSourceId], isNotNull);
    });

    test(
      'permanent failure throws, leaves previous cache and lock untouched',
      () async {
        await fetch(happy());
        final lockBefore = File(cache.lockPath).readAsStringSync();
        final filesBefore = cacheFiles();

        final t = FakeTransport({
          _statusUrl: [overpassStatus()],
          _osmUrl: [status(504)],
          _wdUrl: [ok(wd)],
        });
        await expectLater(
          fetch(t),
          throwsA(
            isA<FetchException>().having(
              (e) => e.message,
              'message',
              contains('untouched'),
            ),
          ),
        );
        expect(File(cache.lockPath).readAsStringSync(), lockBefore);
        expect(cacheFiles(), filesBefore);
        expect(
          t.requests.where((r) => r.url.toString() == _osmUrl),
          hasLength(3),
        );
      },
    );

    test('no first-time cache is created when the first fetch fails', () async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [status(503)],
      });
      await expectLater(fetch(t), throwsA(isA<FetchException>()));
      expect(File(cache.lockPath).existsSync(), isFalse);
      expect(cacheFiles(), isEmpty);
    });

    test(
      'all-or-nothing: Overpass ok but Wikidata fails -> nothing written',
      () async {
        final t = FakeTransport({
          _statusUrl: [overpassStatus()],
          _osmUrl: [ok(osm)],
          _wdUrl: [status(500)],
        });
        await expectLater(fetch(t), throwsA(isA<FetchException>()));
        expect(File(cache.lockPath).existsSync(), isFalse);
        expect(cacheFiles(), isEmpty);
      },
    );

    test('a non-retryable 4xx fails immediately without retries', () async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [status(403)],
      });
      await expectLater(fetch(t), throwsA(isA<FetchException>()));
      expect(
        t.requests.where((r) => r.url.toString() == _osmUrl),
        hasLength(1),
      );
      expect(sleeps, isEmpty);
    });
  });

  group('safe failure: bad or partial payloads', () {
    Future<void> rejects(
      List<int> body, {
      Map<String, String> headers = const {},
      String? mentions,
    }) async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [ok(body, headers: headers)],
        _wdUrl: [ok(wd)],
      });
      await expectLater(
        fetch(t),
        throwsA(
          isA<FetchException>().having(
            (e) => e.message,
            'message',
            mentions == null ? anything : contains(mentions),
          ),
        ),
      );
      expect(
        File(cache.lockPath).existsSync(),
        isFalse,
        reason: 'must not write a lock',
      );
      expect(cacheFiles(), isEmpty);
    }

    test('truncated JSON', () async {
      await rejects(
        osm.sublist(0, osm.length ~/ 2),
        mentions: 'not valid JSON',
      );
    });

    test('HTML error page served with HTTP 200', () async {
      await rejects(
        utf8.encode('<html><body>Error: server too busy</body></html>'),
        mentions: 'JSON',
      );
    });

    test('empty body', () async {
      await rejects(const [], mentions: 'empty');
    });

    test('Overpass runtime remark means partial data -> rejected', () async {
      await rejects(
        overpassBytes(
          [osmNode(1, 'x', 28, 77)],
          extra: {
            'remark':
                'runtime error: Query timed out in "query" at line 3 after 90 seconds.',
          },
        ),
        mentions: 'remark',
      );
    });

    test('missing osm3s timestamp', () async {
      await rejects(
        utf8.encode(jsonEncode({'elements': <Object?>[]})),
        mentions: 'timestamp',
      );
    });

    test('missing elements array', () async {
      await rejects(
        utf8.encode(
          jsonEncode({
            'osm3s': {'timestamp_osm_base': 'x'},
          }),
        ),
        mentions: 'elements',
      );
    });

    test('Content-Length mismatch (incomplete download) is rejected', () async {
      await rejects(
        osm,
        headers: {'content-length': '${osm.length + 500}'},
        mentions: 'incomplete',
      );
    });

    test(
      'Content-Length is ignored when the body was content-encoded',
      () async {
        final t = FakeTransport({
          _statusUrl: [overpassStatus()],
          _osmUrl: [
            ok(
              osm,
              headers: {'content-length': '999', 'content-encoding': 'gzip'},
            ),
          ],
          _wdUrl: [ok(wd)],
        });
        final lock = await fetch(t);
        expect(lock[osmSourceId]!.bytes, osm.length);
      },
    );

    test('too few records (below configured minimum)', () async {
      final strict = testConfig(minOsmRecords: 100);
      final t = happy();
      await expectLater(
        fetcher(t, config: strict).fetchAll(strict, cache: cache),
        throwsA(
          isA<FetchException>().having(
            (e) => e.message,
            'message',
            contains('minimum'),
          ),
        ),
      );
      expect(File(cache.lockPath).existsSync(), isFalse);
    });

    test('invalid SPARQL payload', () async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [ok(osm)],
        _wdUrl: [ok(utf8.encode('{"results": {}}'))],
      });
      await expectLater(fetch(t), throwsA(isA<FetchException>()));
    });
  });

  group('shrink guard (answer much smaller than the last good one)', () {
    test('rejects and keeps the previous data', () async {
      await fetch(happy());
      final small = overpassBytes([osmNode(1, 'x', 28, 77)]);
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [ok(small)],
        _wdUrl: [ok(wd)],
      });
      final before = File(cache.lockPath).readAsStringSync();
      await expectLater(
        fetch(t),
        throwsA(
          isA<FetchException>().having(
            (e) => e.message,
            'message',
            contains('shrank'),
          ),
        ),
      );
      expect(File(cache.lockPath).readAsStringSync(), before);
    });

    test('--accept-shrink overrides it', () async {
      await fetch(happy());
      final small = overpassBytes([osmNode(1, 'x', 28, 77)]);
      final t = FakeTransport({
        _statusUrl: [overpassStatus()],
        _osmUrl: [ok(small)],
        _wdUrl: [ok(wd)],
      });
      final lock = await fetch(t, acceptShrink: true);
      expect(lock[osmSourceId]!.records, 1);
    });
  });

  group('respecting Overpass limits', () {
    test('waits for a free slot instead of querying', () async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus(waitSeconds: 12)],
        _osmUrl: [ok(osm)],
        _wdUrl: [ok(wd)],
      });
      await fetch(t);
      expect(sleeps.first, const Duration(seconds: 13));
      expect(t.requests.first.url.toString(), _statusUrl);
    });

    test('gives up when the slot is further away than the limit', () async {
      final t = FakeTransport({
        _statusUrl: [overpassStatus(waitSeconds: 500)],
        _osmUrl: [ok(osm)],
        _wdUrl: [ok(wd)],
      });
      await expectLater(
        fetch(t),
        throwsA(
          isA<FetchException>().having(
            (e) => e.message,
            'message',
            contains('no free slot'),
          ),
        ),
      );
      expect(t.requests.where((r) => r.url.toString() == _osmUrl), isEmpty);
    });

    test('a failing status endpoint does not block the query', () async {
      final t = FakeTransport({
        _statusUrl: [const SocketException('status down')],
        _osmUrl: [ok(osm)],
        _wdUrl: [ok(wd)],
      });
      await fetch(t);
      expect(cache.readLock()[osmSourceId], isNotNull);
    });
  });

  group('lock and cache integrity', () {
    test('a corrupt lock file is an error, not an empty lock', () {
      Directory(cache.dir).createSync(recursive: true);
      File(cache.lockPath).writeAsStringSync('{ not json');
      expect(() => cache.readLock(), throwsA(isA<LockException>()));
    });

    test('unsupported lock version', () {
      expect(
        () => SourceLock.decode('{"lock_version": 99, "sources": {}}'),
        throwsA(isA<LockException>()),
      );
    });

    test('lock entry missing a field', () {
      expect(
        () => SourceLock.decode(
          '{"lock_version": 1, "sources": {"x": {"file": "f"}}}',
        ),
        throwsA(isA<LockException>()),
      );
    });

    test('modified cache file is detected', () async {
      final lock = await fetch(happy());
      final entry = lock[osmSourceId]!;
      final f = File('${cache.dir}/${entry.file}');
      final bytes = f.readAsBytesSync()..[10] ^= 0xFF;
      f.writeAsBytesSync(bytes);
      expect(() => cache.read(entry), throwsA(isA<LockException>()));
    });

    test('truncated cache file is detected', () async {
      final lock = await fetch(happy());
      final entry = lock[osmSourceId]!;
      final f = File('${cache.dir}/${entry.file}');
      f.writeAsBytesSync(f.readAsBytesSync().sublist(0, 100));
      expect(() => cache.read(entry), throwsA(isA<LockException>()));
    });

    test('missing cache file is detected', () async {
      final lock = await fetch(happy());
      File('${cache.dir}/${lock[osmSourceId]!.file}').deleteSync();
      expect(
        () => cache.read(lock[osmSourceId]!),
        throwsA(
          isA<LockException>().having(
            (e) => e.message,
            'm',
            contains('missing'),
          ),
        ),
      );
    });

    test('latestRetrievedAt gives a deterministic build time', () async {
      final lock = testLock(
        cfg,
        osm,
        wd,
        wdAt: '2026-10-04T09:00:00Z',
      );
      expect(lock.latestRetrievedAt, '2026-10-05T10:00:00Z');
      expect(SourceLock.empty.latestRetrievedAt, isNull);
    });
  });
}
