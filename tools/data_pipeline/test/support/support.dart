import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/data_pipeline.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:sqlite3/sqlite3.dart';

/// All names in the synthetic sources start with "TEST": nothing here
/// describes a real network.

Map<String, Object?> osmNode(
  int id,
  String name,
  double lat,
  double lng, {
  Map<String, String> tags = const {},
}) => {
  'type': 'node',
  'id': id,
  'lat': lat,
  'lon': lng,
  'tags': {'name': name, ...tags},
};

Map<String, Object?> osmRelation(
  int id,
  String name,
  List<int> stopNodes, {
  String ref = 'A',
  String colour = '#112233',
  String? lineQid,
  String? operator = 'TEST Operator',
  String network = 'Test Net',
  String route = 'subway',
}) => {
  'type': 'relation',
  'id': id,
  'members': [
    for (final n in stopNodes) {'type': 'node', 'ref': n, 'role': 'stop'},
    {'type': 'way', 'ref': 9, 'role': ''},
  ],
  'tags': {
    'type': 'route',
    'route': route,
    'network': network,
    'name': name,
    'ref': ref,
    'colour': colour,
    'wikidata': ?lineQid,
    'operator': ?operator,
  },
};

List<int> overpassBytes(
  List<Map<String, Object?>> elements, {
  String version = '2026-10-05T00:00:00Z',
  Map<String, Object?> extra = const {},
}) => utf8.encode(
  jsonEncode({
    'version': 0.6,
    'generator': 'test',
    'osm3s': {'timestamp_osm_base': version},
    'elements': elements,
    ...extra,
  }),
);

/// One SPARQL result row (item + labels + optional line).
Map<String, Object?> wdRow(
  String qid, {
  String? en,
  String? hi,
  double? lat,
  double? lng,
  String? line,
  String? lineEn,
  String? lineHi,
}) {
  Map<String, String> cell(String v) => {'value': v};
  return {
    'item': cell('http://www.wikidata.org/entity/$qid'),
    if (en != null) 'itemLabel_en': cell(en),
    if (hi != null) 'itemLabel_hi': cell(hi),
    if (lat != null && lng != null) 'coord': cell('Point($lng $lat)'),
    if (line != null) 'line': cell('http://www.wikidata.org/entity/$line'),
    if (lineEn != null) 'lineLabel_en': cell(lineEn),
    if (lineHi != null) 'lineLabel_hi': cell(lineHi),
  };
}

List<int> sparqlBytes(List<Map<String, Object?>> rows) => utf8.encode(
  jsonEncode({
    'head': {'vars': <String>[]},
    'results': {'bindings': rows},
  }),
);

/// Mini TEST network: two lines (A, B) that share the station "TEST Central"
/// through a Wikidata id, plus a same-name pair ("TEST East") that is NOT
/// linked (candidate only).
///
///   A: Central -- East(a) -- North        B: Central -- East(b) -- West
class MiniOsm {
  static List<Map<String, Object?>> elements({
    bool northHindi = false,
    Map<int, Map<String, String>> extraTags = const {},
  }) {
    Map<String, String> t(int id, Map<String, String> tags) => {
      ...tags,
      ...?extraTags[id],
    };
    return [
      // ---- line A, forward direction nodes (1xx), reverse nodes (2xx)
      osmNode(
        101,
        'TEST Central',
        28.600,
        77.100,
        tags: t(101, {
          'name:hi': 'टेस्ट सेंट्रल',
          'wikidata': 'Q1000',
          'ref': 'A1',
        }),
      ),
      osmNode(
        102,
        'TEST East',
        28.600,
        77.110,
        tags: t(102, {'name:hi': 'टेस्ट ईस्ट'}),
      ),
      osmNode(
        103,
        'TEST North',
        28.610,
        77.110,
        tags: t(103, northHindi ? {'name:hi': 'टेस्ट नॉर्थ'} : {}),
      ),
      osmNode(201, 'TEST North', 28.6101, 77.1101, tags: t(201, {})),
      osmNode(
        202,
        'TEST East',
        28.6001,
        77.1101,
        tags: t(202, {'name:hi': 'टेस्ट ईस्ट'}),
      ),
      osmNode(
        203,
        'TEST Central',
        28.6001,
        77.1001,
        tags: t(203, {
          'name:hi': 'टेस्ट सेंट्रल',
          'wikidata': 'Q1000',
          'ref': 'A1',
        }),
      ),
      // ---- line B
      osmNode(
        301,
        'TEST Central',
        28.6002,
        77.1002,
        tags: t(301, {
          'name:hi': 'टेस्ट सेंट्रल',
          'wikidata': 'Q1000',
          'ref': 'B1',
        }),
      ),
      osmNode(
        302,
        'TEST East',
        28.603,
        77.112,
        tags: t(302, {'name:hi': 'टेस्ट ईस्ट बी'}),
      ),
      osmNode(
        303,
        'TEST West',
        28.590,
        77.090,
        tags: t(303, {'name:hi': 'टेस्ट वेस्ट'}),
      ),
      osmNode(
        401,
        'TEST West',
        28.5901,
        77.0901,
        tags: t(401, {'name:hi': 'टेस्ट वेस्ट'}),
      ),
      osmNode(
        402,
        'TEST East',
        28.6031,
        77.1121,
        tags: t(402, {'name:hi': 'टेस्ट ईस्ट बी'}),
      ),
      osmNode(
        403,
        'TEST Central',
        28.6003,
        77.1003,
        tags: t(403, {
          'name:hi': 'टेस्ट सेंट्रल',
          'wikidata': 'Q1000',
          'ref': 'B1',
        }),
      ),
      osmRelation(
        11,
        'TEST Alpha Line (TEST Central → TEST North)',
        [101, 102, 103],
        colour: '#C62828',
        lineQid: 'Q9001',
      ),
      osmRelation(
        12,
        'TEST Alpha Line (TEST North → TEST Central)',
        [201, 202, 203],
        colour: '#c62828',
        lineQid: 'Q9001',
      ),
      osmRelation(
        21,
        'TEST Beta Line (TEST Central → TEST West)',
        [301, 302, 303],
        ref: 'B',
        colour: '#1565C0',
        lineQid: 'Q9002',
      ),
      osmRelation(
        22,
        'TEST Beta Line (TEST West → TEST Central)',
        [401, 402, 403],
        ref: 'B',
        colour: '#1565C0',
        lineQid: 'Q9002',
      ),
    ];
  }

  static List<int> bytes({
    bool northHindi = false,
    Map<int, Map<String, String>> extraTags = const {},
  }) => overpassBytes(elements(northHindi: northHindi, extraTags: extraTags));
}

class MiniWd {
  static List<int> bytes({
    String centralEn = 'TEST Central metro station',
    String centralHi = 'टेस्ट सेंट्रल मेट्रो स्टेशन',
    double centralLat = 28.6001,
    double centralLng = 77.1001,
  }) => sparqlBytes([
    wdRow(
      'Q1000',
      en: centralEn,
      hi: centralHi,
      lat: centralLat,
      lng: centralLng,
      line: 'Q9001',
      lineEn: 'TEST Alpha Line',
      lineHi: 'टेस्ट अल्फा लाइन',
    ),
    wdRow(
      'Q1000',
      en: centralEn,
      hi: centralHi,
      lat: centralLat,
      lng: centralLng,
      line: 'Q9002',
      lineEn: 'TEST Beta Line',
      lineHi: 'टेस्ट बीटा लाइन',
    ),
  ]);
}

PipelineConfig testConfig({
  NormalizationRules? normalization,
  double maxClusterSpreadM = 800,
  double coordinateConflictM = 250,
  double mergeCandidateRadiusM = 500,
  int minOsmRecords = 1,
  int minWdRecords = 1,
  FetchSettings fetch = const FetchSettings(
    maxDelay: Duration(seconds: 120),
    maxSlotWait: Duration(seconds: 60),
  ),
}) => PipelineConfig(
  city: 'testville',
  bbox: '28.0,76.0,29.0,78.0',
  maxClusterSpreadM: maxClusterSpreadM,
  coordinateConflictM: coordinateConflictM,
  mergeCandidateRadiusM: mergeCandidateRadiusM,
  curatedOverlayPath: 'data/curated/overlays.yaml',
  fetch: fetch,
  remote: [
    RemoteSource(
      id: osmSourceId,
      kind: RemoteKind.overpass,
      name: 'TEST OSM',
      license: 'ODbL-1.0',
      licenseUrl: 'https://example.invalid/odbl',
      attribution: 'TEST (c) OpenStreetMap contributors (ODbL).',
      endpoints: const ['https://overpass.test/api/interpreter'],
      query: '[out:json]; test-osm-query;',
      queryFile: 'data/sources/queries/osm.overpassql',
      minRecords: minOsmRecords,
      network: 'Test Net',
    ),
    RemoteSource(
      id: wikidataSourceId,
      kind: RemoteKind.sparql,
      name: 'TEST Wikidata',
      license: 'CC0-1.0',
      licenseUrl: 'https://example.invalid/cc0',
      attribution: 'TEST Wikidata (CC0).',
      endpoints: const ['https://sparql.test/sparql'],
      query: 'SELECT * WHERE { test-sparql }',
      queryFile: 'data/sources/queries/wd.rq',
      minRecords: minWdRecords,
    ),
  ],
  local: const [
    LocalSource(
      id: curatedSourceId,
      name: 'TEST curated',
      license: 'test',
      notes: '',
    ),
    LocalSource(
      id: derivedSourceId,
      name: 'TEST derived',
      license: 'test',
      notes: '',
    ),
  ],
  normalization:
      normalization ??
      const NormalizationRules(
        stripSuffixesEn: [' metro station'],
        stripSuffixesHi: [' मेट्रो स्टेशन'],
        candidateStripPattern: r'\s*\([^)]*Line\)\s*$',
      ),
);

/// Lock with entries for both sources (hashes are for the given bytes).
SourceLock testLock(
  PipelineConfig cfg,
  List<int> osm,
  List<int> wd, {
  String osmAt = '2026-10-05T10:00:00Z',
  String wdAt = '2026-10-05T11:00:00Z',
}) {
  LockEntry entry(RemoteSource s, List<int> b, String at, int records) =>
      LockEntry(
        sourceId: s.id,
        file: '${s.id}.${sha256Hex(b).substring(0, 12)}.json',
        sha256: sha256Hex(b),
        bytes: b.length,
        records: records,
        retrievedAt: at,
        requestSha256: sha256Hex(utf8.encode(s.query)),
        endpoint: s.endpoints.first,
        license: s.license,
        sourceVersion: s.id == osmSourceId ? '2026-10-05T09:59:00Z' : null,
      );
  return SourceLock({
    osmSourceId: entry(cfg.remoteById(osmSourceId), osm, osmAt, 16),
    wikidataSourceId: entry(cfg.remoteById(wikidataSourceId), wd, wdAt, 2),
  });
}

/// A temp repository root with sources.yaml, query files, cache + lock.
class Workspace {
  Workspace._(this.dir);

  final Directory dir;
  String get root => dir.path;

  static Workspace create({
    List<int>? osm,
    List<int>? wd,
    String overlay = '',
    bool writeCache = true,
  }) {
    final dir = Directory.systemTemp.createTempSync('pipeline_ws_');
    final w = Workspace._(dir);
    final osmBytes = osm ?? MiniOsm.bytes();
    final wdBytes = wd ?? MiniWd.bytes();
    File('${dir.path}/data/sources/queries/osm.overpassql')
      ..createSync(recursive: true)
      ..writeAsStringSync('[out:json]; test-osm-query;');
    File('${dir.path}/data/sources/queries/wd.rq')
      ..createSync(recursive: true)
      ..writeAsStringSync('SELECT * WHERE { test-sparql }');
    File('${dir.path}/data/sources/sources.yaml').writeAsStringSync(r'''
dataset:
  city: testville
  bbox: "28.0,76.0,29.0,78.0"
  curated_overlay: data/curated/overlays.yaml
remote:
  - id: osm-overpass
    kind: overpass
    name: "TEST OSM"
    license: ODbL-1.0
    license_url: https://example.invalid/odbl
    attribution: "TEST (c) OpenStreetMap contributors (ODbL)."
    endpoints: [https://overpass.test/api/interpreter]
    query_file: data/sources/queries/osm.overpassql
    network: "Test Net"
  - id: wikidata
    kind: sparql
    name: "TEST Wikidata"
    license: CC0-1.0
    license_url: https://example.invalid/cc0
    attribution: "TEST Wikidata (CC0)."
    endpoint: https://sparql.test/sparql
    query_file: data/sources/queries/wd.rq
local:
  - {id: mitra-curated, name: "TEST curated", license: test}
  - {id: mitra-derived, name: "TEST derived", license: test}
normalization:
  strip_suffixes_en: [" metro station"]
  strip_suffixes_hi: [" मेट्रो स्टेशन"]
  candidate_strip_pattern: '\s*\([^)]*Line\)\s*$'
''');
    File('${dir.path}/data/curated/overlays.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(overlay);
    if (writeCache) w.writeCache(osmBytes, wdBytes);
    return w;
  }

  void writeCache(
    List<int> osm,
    List<int> wd, {
    String osmAt = '2026-10-05T10:00:00Z',
    String wdAt = '2026-10-05T11:00:00Z',
  }) {
    final cfg = PipelineConfig.load(
      '$root/data/sources/sources.yaml',
      root: root,
    );
    final lock = testLock(cfg, osm, wd, osmAt: osmAt, wdAt: wdAt);
    Directory('$root/data/cache').createSync(recursive: true);
    for (final (id, bytes) in [(osmSourceId, osm), (wikidataSourceId, wd)]) {
      File('$root/data/cache/${lock[id]!.file}').writeAsBytesSync(bytes);
    }
    lock.write('$root/data/cache/sources.lock.json');
  }

  BuildPaths get paths => BuildPaths(root: root);

  void dispose() => dir.deleteSync(recursive: true);
}

/// Scripted network: each call to [send] pops the next response/exception for
/// the URL (or the last one repeats). Records every request.
class FakeTransport implements HttpTransport {
  FakeTransport(this.script);

  /// url prefix -> queue of outcomes (HttpResponse or Exception).
  final Map<String, List<Object>> script;
  final List<HttpRequest> requests = [];

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    requests.add(request);
    final key = script.keys.firstWhere(
      (k) => request.url.toString().startsWith(k),
      orElse: () => throw StateError('unexpected request ${request.url}'),
    );
    final queue = script[key]!;
    final next = queue.length > 1 ? queue.removeAt(0) : queue.first;
    if (next is Exception) throw next;
    return next as HttpResponse;
  }
}

HttpResponse ok(List<int> bytes, {Map<String, String> headers = const {}}) =>
    HttpResponse(200, bytes, headers);

HttpResponse status(int code, [Map<String, String> headers = const {}]) =>
    HttpResponse(code, utf8.encode('error $code'), headers);

HttpResponse overpassStatus({int slots = 4, int? waitSeconds}) => HttpResponse(
  200,
  utf8.encode(
    waitSeconds == null
        ? 'Connected as: 1\n$slots slots available now.\n'
        : 'Connected as: 1\n0 slots available now.\nSlot available after: x, in $waitSeconds seconds.\n',
  ),
);

/// In-memory dataset database with foreign keys switched OFF afterwards, so
/// tests can delete rows directly (e.g. remove a line) and diff the result.
Database memoryDb(MetroSnapshot s) {
  final db = sqlite3.openInMemory();
  DatasetWriter.write(s, db);
  db.execute('PRAGMA foreign_keys = OFF');
  return db;
}
