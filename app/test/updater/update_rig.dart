import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/dataset_bootstrap.dart';
import 'package:metromitra/shared/data/updater/dataset_store.dart';
import 'package:metromitra/shared/data/updater/dataset_updater.dart';
import 'package:metromitra/shared/data/updater/update_transport.dart';

const fixturePath = '../data/fixtures/mini_network/dataset.yaml';

/// Test signing key: a throwaway made for tests. The private seed lives only
/// in test code; the app holds public keys only.
final testSeed = List<int>.generate(32, (i) => i + 1);
final otherSeed = List<int>.generate(32, (i) => 100 + i);

Future<TrustedKey> keyFor(List<int> seed) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  return TrustedKey((await pair.extractPublicKey()).bytes);
}

/// A signed manifest map for [file]. [tweak] edits the fields before signing,
/// [afterSign] after (tampering).
Future<Map<String, Object?>> signedManifest(
  File file, {
  required String version,
  required String url,
  List<int>? seed,
  void Function(Map<String, Object?>)? tweak,
  void Function(Map<String, Object?>)? afterSign,
}) async {
  final bytes = file.readAsBytesSync();
  final key = await keyFor(seed ?? testSeed);
  final m = <String, Object?>{
    'dataset_version': version,
    'schema_version': currentSchemaVersion,
    'stage': 'release',
    'min_app_version': '0.1.0',
    'released_at': '2026-10-08T00:00:00Z',
    'url': url,
    'size': bytes.length,
    'sha256': contentSha256Hex(bytes),
    'attribution': 'TEST DATA',
    'sources': <Object?>[],
    'changelog': {'en': 'test update'},
    'signature_alg': 'ed25519',
    'key_id': key.id,
  };
  tweak?.call(m);
  final pair = await DartEd25519().newKeyPairFromSeed(seed ?? testSeed);
  final sig = await DartEd25519().sign(
    canonicalManifestBytes(m),
    keyPair: pair,
  );
  m['signature'] = base64Encode(sig.bytes);
  afterSign?.call(m);
  return m;
}

/// Writes the fixture dataset as [version] to [path] (TEST DATA).
File writeDataset(String path, String version) {
  final snap = YamlDatasetLoader.loadFile(fixturePath);
  DatasetWriter.writeFile(
    snap.copyWith(meta: {...snap.meta, 'dataset_version': version}),
    path,
  );
  return File(path);
}

/// A scripted local HTTP server standing in for the update host.
class TestServer {
  TestServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<TestServer> start() async =>
      TestServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final files = <String, List<int>>{};
  final requests = <String>[];
  final rangeHeaders = <String>[];

  /// Path -> bytes after which the connection is cut (interrupted download).
  final cutAfter = <String, int>{};

  /// Paths that never answer (timeout).
  final hang = <String>{};

  /// Path -> status code to answer with instead of the file.
  final status = <String, int>{};

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  void putManifest(Map<String, Object?> m) =>
      files['/manifest.json'] = utf8.encode(jsonEncode(m));

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest r) async {
    final path = r.uri.path;
    requests.add(path);
    if (hang.contains(path)) return;
    final code = status[path];
    if (code != null) {
      r.response.statusCode = code;
      await r.response.close();
      return;
    }
    final data = files[path];
    if (data == null) {
      r.response.statusCode = 404;
      await r.response.close();
      return;
    }
    var start = 0;
    final range = r.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      rangeHeaders.add(range);
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      r.response.statusCode = HttpStatus.partialContent;
    }
    final body = data.sublist(start);
    final cut = cutAfter.remove(path);
    if (cut != null) {
      // promise the whole body, send part of it, drop the connection
      final socket = await r.response.detachSocket(writeHeaders: false);
      final line = start > 0 ? '206 Partial Content' : '200 OK';
      socket
        ..add(
          utf8.encode(
            'HTTP/1.1 $line\r\nContent-Length: ${body.length}\r\n\r\n',
          ),
        )
        ..add(body.sublist(0, cut));
      await socket.flush();
      socket.destroy();
      return;
    }
    r.response.contentLength = body.length;
    r.response.add(body);
    await r.response.close();
  }
}

/// Temp app storage + store + server + updater, for one test.
class UpdateRig {
  UpdateRig._(this.dir, this.store, this.server, this.updater);

  final Directory dir;
  final DatasetStore store;
  final TestServer server;
  final DatasetUpdater updater;

  static Future<UpdateRig> create({
    String? bundledVersion,
    List<List<int>>? seeds,
    String appVersion = '0.1.0',
    DatasetPolicy policy = const DatasetPolicy(allowTestData: true),
    Duration idle = const Duration(seconds: 2),
  }) async {
    final dir = Directory.systemTemp.createTempSync('mm_update_');
    final store = DatasetStore(Directory('${dir.path}/datasets'));
    final server = await TestServer.start();
    final keys = [
      for (final s in seeds ?? [testSeed]) await keyFor(s),
    ];
    final updater = DatasetUpdater(
      store: store,
      transport: HttpUpdateTransport(
        allowInsecureLoopback: true,
        idleTimeout: idle,
        connectTimeout: const Duration(seconds: 2),
      ),
      verifier: ManifestVerifier(keys),
      appVersion: appVersion,
      manifestUrl: server.url('/manifest.json'),
      policy: policy,
      loader: loadDatasetSync,
      bundledVersion: bundledVersion,
    );
    return UpdateRig._(dir, store, server, updater);
  }

  /// Dataset [version] built in a scratch folder, served at `/<version>.sqlite`
  /// (or `.gz`), with its manifest published at `/manifest.json`.
  Future<File> publish(
    String version, {
    bool gz = false,
    void Function(Map<String, Object?>)? tweak,
    void Function(Map<String, Object?>)? afterSign,
    List<int>? seed,
    List<int> Function(List<int> bytes)? corruptServed,
    File? source,
  }) async {
    final file =
        source ?? writeDataset('${dir.path}/src-$version.sqlite', version);
    final name = gz ? '/$version.sqlite.gz' : '/$version.sqlite';
    final raw = file.readAsBytesSync();
    var served = gz ? gzip.encode(raw) : raw;
    if (corruptServed != null) served = corruptServed(served);
    server.files[name] = served;
    server.putManifest(
      await signedManifest(
        file,
        version: version,
        url: server.url(name).toString(),
        seed: seed,
        tweak: tweak,
        afterSign: afterSign,
      ),
    );
    return file;
  }

  /// What the app loads at launch: installed datasets, then [bundled].
  Future<BootstrapResult> launch({File? bundled}) => bootstrapDataset(
    candidates: [
      ...store.candidates(),
      if (bundled != null)
        DatasetCandidate(label: 'bundled', path: bundled.path),
    ],
    policy: const DatasetPolicy(allowTestData: true),
  );

  Future<void> dispose() async {
    await server.close();
    try {
      dir.deleteSync(recursive: true);
    } on Object {
      // temp dir
    }
  }
}

String? versionOf(BootstrapResult r) =>
    r is BootstrapReady ? r.snapshot.datasetVersion : null;

String? labelOf(BootstrapResult r) =>
    r is BootstrapReady ? r.sourceLabel : null;
