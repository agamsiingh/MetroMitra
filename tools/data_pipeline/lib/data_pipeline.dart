/// MetroMitra dataset pipeline.
///
/// fetch (Overpass + Wikidata, locked, cached) -> normalize -> curated
/// overlays -> conflict check -> canonical dataset -> validation -> sqlite,
/// plus diff, sign/verify and inspect. Schema, validation and the sqlite
/// writer/reader are shared with the app through `metro_core`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/src/config.dart';
import 'package:data_pipeline/src/diff.dart';
import 'package:data_pipeline/src/fetch.dart';
import 'package:data_pipeline/src/lock.dart';
import 'package:data_pipeline/src/normalize.dart';
import 'package:data_pipeline/src/overlay.dart';
import 'package:data_pipeline/src/pipeline.dart';
import 'package:data_pipeline/src/reference_check.dart';
import 'package:data_pipeline/src/route_report.dart';
import 'package:data_pipeline/src/search_report.dart';
import 'package:data_pipeline/src/signing.dart';
import 'package:data_pipeline/src/util.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:sqlite3/sqlite3.dart';
import 'package:yaml/yaml.dart';

export 'package:data_pipeline/src/config.dart';
export 'package:data_pipeline/src/conflict.dart';
export 'package:data_pipeline/src/diff.dart';
export 'package:data_pipeline/src/fetch.dart';
export 'package:data_pipeline/src/lock.dart';
export 'package:data_pipeline/src/merge.dart';
export 'package:data_pipeline/src/normalize.dart';
export 'package:data_pipeline/src/overlay.dart';
export 'package:data_pipeline/src/pipeline.dart';
export 'package:data_pipeline/src/reference_check.dart';
export 'package:data_pipeline/src/route_report.dart';
export 'package:data_pipeline/src/search_report.dart';
export 'package:data_pipeline/src/signing.dart';
export 'package:data_pipeline/src/util.dart';

const List<String> pipelineCommands = [
  'fetch',
  'build',
  'validate',
  'diff',
  'sign',
  'verify',
  'keygen',
  'inspect',
  'route',
  'search',
  'reference',
];

const defaultInput = 'data/fixtures/mini_network/dataset.yaml';
const defaultOutput = 'build/pipeline/metro.sqlite';

const _usage =
    '''
MetroMitra data pipeline

  fetch    [--accept-shrink] [--only <id,id>]
           Download OSM (Overpass) + Wikidata into data/cache, update
           data/cache/sources.lock.json. All-or-nothing; failures leave the
           cache untouched.
  build    [--out f] [--report f] [--admin-export f] [--require-release]
           Offline rebuild from the locked cache + data/curated overlays:
           normalise -> overlays -> conflict check -> validate -> sqlite.
           Writes build/pipeline/build-report.json (conflicts, provenance).
  build    --input <dataset.yaml> [--out f] [--allow-test-data]
           Compile an authoring YAML (test fixtures) instead.
  validate [--input <yaml|sqlite>] [--draft]
  diff     <old.sqlite> <new.sqlite> [--json]
  sign     --input <sqlite> [--out manifest.json] [--min-app-version v]
           [--url u] [--changelog-file f] [--allow-draft]   (key: \$$signingKeyEnv)
  verify   --manifest <f> --public-key <base64|file> [--input <sqlite>]
  keygen   --private-out <file>        (prints the public key)
  inspect  --input <sqlite> [--table t] [--limit n]
  search   <query> [--input <sqlite>] [--limit n] [--stations|--lines] [--all] [--json]
           Search stations and lines (English, Hindi, aliases, codes, typos) in a
           built dataset (drafts allowed). `search --self-check` looks every
           station up by its own names/codes and fails on any problem.
  route    <from-id> <to-id> [--input <sqlite>] [--minute m] [--json]
           Plan a trip on a built dataset (drafts allowed): all profiles, fare
           (only from dataset fare data), warnings. `route --components`
           lists disconnected parts of the network instead.

  reference [--input <sqlite>] [--reference <yaml>]
           Compare per-line station counts and lengths with an official
           reference (default data/curated/reference/dmrc_network_2026-08.yaml).
           Fails on a count difference that is not in its `accepted` list.

Exit codes: 0 ok, 1 invalid data / blocking conflicts, 2 refused, 3 network
failure, 4 missing/stale inputs, 64 usage.''';

/// Runs the CLI; returns the process exit code.
Future<int> run(
  List<String> args, {
  void Function(String) out = print,
  void Function(String) err = _stderr,
  HttpTransport? transport,
  Sleeper? sleep,
  DateTime Function()? now,
  Map<String, String>? environment,
  BuildPaths paths = const BuildPaths(),
}) async {
  final rest = args.where((a) => a != '--offline').toList();
  if (rest.isEmpty || rest.first == '--help' || rest.first == '-h') {
    out(_usage);
    return rest.isEmpty ? 64 : 0;
  }
  final command = rest.first;
  if (!pipelineCommands.contains(command)) {
    err('Unknown command "$command".\n$_usage');
    return 64;
  }
  final _Args a;
  try {
    a = _Args.parse(rest.skip(1).toList());
  } on FormatException catch (e) {
    err(e.message);
    return 64;
  }
  final env = environment ?? Platform.environment;

  try {
    switch (command) {
      case 'fetch':
        return await _fetch(a, paths, transport, sleep, now, env, out, err);
      case 'build':
        return a.has('input')
            ? _buildYaml(a, out, err)
            : _buildReal(a, paths, now, out, err);
      case 'validate':
        return _validate(a, out, err);
      case 'diff':
        return _diff(a, out, err);
      case 'sign':
        return await _sign(a, env, out, err);
      case 'verify':
        return await _verify(a, out, err);
      case 'keygen':
        return await _keygen(a, out, err);
      case 'inspect':
        return _inspect(a, out, err);
      case 'route':
        return _route(a, out, err);
      case 'reference':
        return _reference(a, out, err);
      case 'search':
        return _search(a, out, err);
    }
    return 64;
  } on AuthoringException catch (e) {
    err('Authoring error: ${e.message}');
    return 1;
  } on DatasetException catch (e) {
    err('Dataset error: $e');
    return 1;
  } on ConfigException catch (e) {
    err('Configuration error: ${e.message}');
    return 4;
  } on InputException catch (e) {
    err('Input error: ${e.message}');
    return 4;
  } on LockException catch (e) {
    err('Lock error: ${e.message}');
    return 4;
  } on OverlayException catch (e) {
    err('Overlay error: ${e.message}');
    return 1;
  } on SourceFormatException catch (e) {
    err('Source data error (${e.source}): ${e.message}');
    return 1;
  } on FetchException catch (e) {
    err('Fetch failed: $e');
    return 3;
  } on SigningException catch (e) {
    err('Signing error: ${e.message}');
    return 2;
  } on SqliteException catch (e) {
    err('Database error: ${e.message}');
    return 1;
  } on FileSystemException catch (e) {
    err('File error: ${e.message} ${e.path ?? ''}');
    return 1;
  }
}

void _stderr(String s) => stderr.writeln(s);

class _Args {
  _Args(this.options, this.positional);

  static const flags = {
    'allow-test-data',
    'accept-shrink',
    'require-release',
    'draft',
    'json',
    'allow-draft',
    'components',
    'self-check',
    'stations',
    'lines',
    'all',
  };
  static const valued = {
    'input',
    'out',
    'report',
    'admin-export',
    'only',
    'table',
    'limit',
    'manifest',
    'public-key',
    'private-out',
    'min-app-version',
    'url',
    'changelog-file',
    'minute',
  };

  final Map<String, String?> options;
  final List<String> positional;

  bool has(String k) => options.containsKey(k);
  String? operator [](String k) => options[k];

  // A named static entry point reads better than a factory constructor here.
  // ignore: prefer_constructors_over_static_methods
  static _Args parse(List<String> args) {
    final options = <String, String?>{};
    final positional = <String>[];
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (!a.startsWith('--')) {
        positional.add(a);
        continue;
      }
      final name = a.substring(2);
      if (flags.contains(name)) {
        options[name] = null;
      } else if (valued.contains(name)) {
        if (i + 1 >= args.length) {
          throw FormatException('--$name needs a value');
        }
        options[name] = args[++i];
      } else {
        throw FormatException('Unknown option "$a"');
      }
    }
    return _Args(options, positional);
  }
}

// ---------------------------------------------------------------- fetch

Future<int> _fetch(
  _Args a,
  BuildPaths p,
  HttpTransport? transport,
  Sleeper? sleep,
  DateTime Function()? now,
  Map<String, String> env,
  void Function(String) out,
  void Function(String) err,
) async {
  final config = PipelineConfig.load(
    resolvePath(p.root, p.config),
    root: p.root,
  );
  final contact = env['METROMITRA_CONTACT'];
  final fetcher = Fetcher(
    transport:
        transport ?? IoHttpTransport(timeout: config.fetch.requestTimeout),
    settings: config.fetch,
    userAgent:
        'MetroMitra-data-pipeline/$pipelineVersion'
        '${contact == null ? '' : ' (contact: $contact)'}',
    now: now,
    sleep: sleep,
  );
  final lock = await fetcher.fetchAll(
    config,
    cache: RawCache(
      resolvePath(p.root, p.cacheDir),
      resolvePath(p.root, p.lock),
    ),
    acceptShrink: a.has('accept-shrink'),
    only: a['only']?.split(',').toSet(),
    log: out,
  );
  for (final e in lock.entries.values) {
    out(
      'locked ${e.sourceId}: ${e.records} records, ${e.bytes} bytes, '
      'sha256 ${e.sha256.substring(0, 12)}, ${e.sourceVersion ?? e.retrievedAt}',
    );
  }
  return 0;
}

// ---------------------------------------------------------------- build

int _buildReal(
  _Args a,
  BuildPaths base,
  DateTime Function()? now,
  void Function(String) out,
  void Function(String) err,
) {
  final paths = BuildPaths(
    root: base.root,
    config: base.config,
    cacheDir: base.cacheDir,
    lock: base.lock,
    out: a['out'] ?? base.out,
    report: a['report'] ?? base.report,
    adminExport: a['admin-export'] ?? base.adminExport,
  );
  final outcome = buildDataset(
    paths,
    requireRelease: a.has('require-release'),
    now: now?.call(),
    log: out,
  );
  final conflicts = outcome.report['conflicts']! as Map<String, Object?>;
  final dataset = outcome.report['dataset']! as Map<String, Object?>;
  out(
    'stage: ${outcome.stage}; ${dataset['stations']} stations, '
    '${dataset['lines']} lines, ${dataset['services']} services, '
    '${dataset['edges']} edges; conflicts ${conflicts['total']} '
    '(${conflicts['blocking']} blocking). Report: ${paths.report}',
  );
  for (final c in outcome.conflicts.where((c) => c.blocking).take(20)) {
    err('BLOCKING [${c.kind}] ${c.subject}: ${c.message}');
  }
  final validation = outcome.report['validation']! as Map<String, Object?>;
  for (final e in ((validation['draft']! as Map)['errors']! as List).take(20)) {
    err('INVALID $e');
  }
  if (outcome.stage == 'failed') {
    err('Build failed: no dataset written. See ${paths.report}.');
    return 1;
  }
  if (!outcome.ok) {
    err(
      'Stage is "${outcome.stage}" but --require-release was given; '
      'no dataset written.',
    );
    return 1;
  }
  out('Wrote ${paths.out} (sha256 ${outcome.outputSha256})');
  if (outcome.stage == 'draft') {
    out(
      'DRAFT dataset: valid structurally but incomplete (see report). '
      'It cannot be signed or released.',
    );
  }
  return 0;
}

MetroSnapshot _load(
  String input, {
  ValidationMode mode = ValidationMode.release,
}) => input.endsWith('.sqlite')
    ? DatasetReader.readFile(input, validate: false, mode: mode)
    : YamlDatasetLoader.loadFile(input);

int _buildYaml(_Args a, void Function(String) out, void Function(String) err) {
  final input = a['input']!;
  final outPath = a['out'] ?? defaultOutput;
  final snapshot = _load(input);
  if (snapshot.isTestData && !a.has('allow-test-data')) {
    err(
      'Refusing to build "$input": it is marked TEST DATA '
      '(meta.is_test_data). Pass --allow-test-data for test builds only.',
    );
    return 2;
  }
  final report = validateSnapshot(snapshot);
  _printIssues(report, out, err);
  if (!report.isValid) {
    err('Build aborted: ${report.errors.length} validation error(s).');
    return 1;
  }
  DatasetWriter.writeFile(snapshot, outPath);
  final back = DatasetReader.readFile(outPath);
  out(
    'Built $outPath: dataset ${back.datasetVersion}, schema '
    'v${back.schemaVersion}, ${back.stations.length} stations, '
    '${back.lines.length} lines, ${back.edges.length} edges '
    '(${report.warnings.length} warning(s))'
    '${snapshot.isTestData ? ' [TEST DATA]' : ''}',
  );
  return 0;
}

int _validate(_Args a, void Function(String) out, void Function(String) err) {
  final input = a['input'] ?? defaultInput;
  final mode = a.has('draft') ? ValidationMode.draft : ValidationMode.release;
  final report = validateSnapshot(_load(input, mode: mode), mode: mode);
  _printIssues(report, out, err);
  out(
    report.isValid
        ? 'OK: ${report.warnings.length} warning(s)'
        : 'INVALID: ${report.errors.length} error(s), '
              '${report.warnings.length} warning(s)',
  );
  return report.isValid ? 0 : 1;
}

void _printIssues(
  ValidationReport report,
  void Function(String) out,
  void Function(String) err,
) {
  for (final i in report.errors.take(50)) {
    err('$i');
  }
  if (report.errors.length > 50) {
    err('... ${report.errors.length - 50} more errors');
  }
  final counts = <String, int>{};
  for (final w in report.warnings) {
    counts[w.code] = (counts[w.code] ?? 0) + 1;
  }
  for (final e
      in counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    out('WARNING [${e.key}] x${e.value}');
  }
}

// ---------------------------------------------------------------- diff etc.

int _diff(_Args a, void Function(String) out, void Function(String) err) {
  if (a.positional.length != 2) {
    err('diff needs <old.sqlite> <new.sqlite>');
    return 64;
  }
  final d = diffFiles(a.positional[0], a.positional[1]);
  out(a.has('json') ? canonicalJson(d.toJson()) : d.toText());
  return 0;
}

Future<int> _sign(
  _Args a,
  Map<String, String> env,
  void Function(String) out,
  void Function(String) err,
) async {
  final input = a['input'];
  if (input == null) {
    err('sign needs --input <sqlite>');
    return 64;
  }
  final key = env[signingKeyEnv];
  if (key == null || key.isEmpty) {
    err('Set $signingKeyEnv (base64 Ed25519 seed; CI secret store only).');
    return 2;
  }
  final List<int> seed;
  try {
    seed = base64Decode(key.trim());
  } on FormatException {
    err('$signingKeyEnv is not valid base64.');
    return 2;
  }
  final changelog = a['changelog-file'];
  final manifest = buildManifest(
    input,
    minAppVersion: a['min-app-version'] ?? '1.0.0',
    url: a['url'],
    changelog: changelog == null
        ? null
        : {
            'en': File(changelog).readAsStringSync().trim(),
          },
    allowDraft: a.has('allow-draft'),
  );
  final signed = await signManifest(manifest, seed);
  final outPath = a['out'] ?? '${File(input).parent.path}/manifest.json';
  File(outPath).writeAsStringSync(canonicalJson(signed));
  out(
    'Signed ${manifest['dataset_version']} -> $outPath (key ${signed['key_id']})',
  );
  return 0;
}

Future<int> _verify(
  _Args a,
  void Function(String) out,
  void Function(String) err,
) async {
  final manifestPath = a['manifest'];
  final keyArg = a['public-key'];
  if (manifestPath == null || keyArg == null) {
    err('verify needs --manifest and --public-key');
    return 64;
  }
  final keyText = File(keyArg).existsSync()
      ? File(keyArg).readAsStringSync()
      : keyArg;
  final Object? manifest;
  final List<int> publicKey;
  try {
    manifest = jsonDecode(File(manifestPath).readAsStringSync());
    publicKey = base64Decode(keyText.trim());
  } on FormatException catch (e) {
    err('Cannot parse manifest or key: ${e.message}');
    return 1;
  }
  if (manifest is! Map<String, Object?>) {
    err('Manifest is not a JSON object.');
    return 1;
  }
  final r = await verifyManifest(manifest, publicKey, sqlitePath: a['input']);
  if (r.ok) {
    out(
      'OK: signature valid${a.has('input') ? ', file matches size and sha256' : ''}.',
    );
    return 0;
  }
  for (final p in r.problems) {
    err('VERIFY FAILED: $p');
  }
  return 1;
}

Future<int> _keygen(
  _Args a,
  void Function(String) out,
  void Function(String) err,
) async {
  final target = a['private-out'];
  if (target == null) {
    err('keygen needs --private-out <file> (outside the repository!)');
    return 64;
  }
  if (File(target).existsSync()) {
    err('Refusing to overwrite $target');
    return 2;
  }
  final key = await generateKey();
  File(target).writeAsStringSync(base64Encode(key.privateSeed));
  out('Private seed written to $target (keep it secret; never commit).');
  out('Public key (embed in the app): ${base64Encode(key.publicKey)}');
  out('Key id: ${keyId(key.publicKey)}');
  return 0;
}

int _inspect(_Args a, void Function(String) out, void Function(String) err) {
  final input = a['input'] ?? defaultOutput;
  if (!File(input).existsSync()) {
    err('No dataset at $input');
    return 4;
  }
  final db = sqlite3.open(input, mode: OpenMode.readOnly);
  try {
    final table = a['table'];
    if (table == null) {
      for (final r in db.select('SELECT key, value FROM meta ORDER BY key')) {
        out('meta.${r['key']} = ${r['value']}');
      }
      for (final t in schemaTables) {
        final n = db.select('SELECT COUNT(*) c FROM $t').first['c'];
        out('$t: $n');
      }
      return 0;
    }
    if (!schemaTables.contains(table)) {
      err('Unknown table "$table"');
      return 64;
    }
    final limit = int.tryParse(a['limit'] ?? '') ?? 20;
    for (final row in db.select('SELECT * FROM $table LIMIT $limit')) {
      out(jsonEncode({for (final k in row.keys) k: row[k]}));
    }
    return 0;
  } finally {
    db.close();
  }
}

// ---------------------------------------------------------------- route

int _reference(
  _Args a,
  void Function(String) out,
  void Function(String) err,
) {
  final input = a['input'] ?? defaultOutput;
  final refPath =
      a['reference'] ?? 'data/curated/reference/dmrc_network_2026-08.yaml';
  if (!File(input).existsSync() || !File(refPath).existsSync()) {
    err('Need a dataset ($input) and a reference ($refPath).');
    return 4;
  }
  final snapshot = DatasetReader.readFile(input, mode: ValidationMode.draft);
  final ref = loadYaml(File(refPath).readAsStringSync()) as YamlMap;
  final report = checkReference(snapshot, ref);
  formatReference(report).forEach(out);
  final bad = report.unexplained;
  if (bad.isNotEmpty) {
    err(
      'Unexplained station-count differences: '
      '${bad.map((r) => '${r.no} ${r.name}').join(', ')}',
    );
    return 1;
  }
  out('OK: every difference is documented.');
  return 0;
}

int _route(_Args a, void Function(String) out, void Function(String) err) {
  final input = a['input'] ?? defaultOutput;
  if (!File(input).existsSync()) {
    err('No dataset at $input');
    return 4;
  }
  final snapshot = DatasetReader.readFile(input, mode: ValidationMode.draft);
  final planner = RoutePlanner(snapshot, fareEngine: FareEngine(snapshot));
  if (a.has('components')) {
    final parts = planner.stationComponents();
    out('${parts.length} connected part(s)');
    for (final c in parts) {
      out(
        '${c.length} stations: ${c.take(8).join(', ')}${c.length > 8 ? ', ...' : ''}',
      );
    }
    return 0;
  }
  if (a.positional.length != 2) {
    err('route needs <from-id> <to-id>');
    return 64;
  }
  final minute = int.tryParse(a['minute'] ?? '');
  final result = planner.plan(
    a.positional[0],
    a.positional[1],
    fareRequest: FareRequest(minuteOfDay: minute),
  );
  if (!result.isOk) {
    err('No route: ${result.status.name} ${result.detail ?? ''}');
    return 1;
  }
  if (a.has('json')) {
    out(
      canonicalJson({
        'status': result.status.name,
        'itineraries': [for (final i in result.itineraries) itineraryJson(i)],
      }),
    );
  } else {
    for (final it in result.itineraries) {
      describeItinerary(snapshot, it).forEach(out);
    }
  }
  return 0;
}

// ---------------------------------------------------------------- search

int _search(_Args a, void Function(String) out, void Function(String) err) {
  final input = a['input'] ?? defaultOutput;
  if (!File(input).existsSync()) {
    err('No dataset at $input');
    return 4;
  }
  final snapshot = DatasetReader.readFile(input, mode: ValidationMode.draft);
  final index = SearchIndex.fromSnapshot(snapshot);
  if (a.has('self-check')) {
    final problems = index.selfCheck();
    problems.take(50).forEach(err);
    out(
      problems.isEmpty
          ? 'OK: ${index.entryCount} names/codes of ${index.entityCount} '
                'stations and lines found by their own text'
          : 'SELF-CHECK FAILED: ${problems.length} problem(s)',
    );
    return problems.isEmpty ? 0 : 1;
  }
  if (a.positional.length != 1) {
    err('search needs one <query> (quote it)');
    return 64;
  }
  final limit = int.tryParse(a['limit'] ?? '') ?? 10;
  final scope = a.has('stations')
      ? SearchScope.stations
      : a.has('lines')
      ? SearchScope.lines
      : SearchScope.all;
  final results = index.search(
    a.positional.single,
    options: SearchOptions(limit: limit, scope: scope, onlyOpen: !a.has('all')),
  );
  if (a.has('json')) {
    out(
      canonicalJson({
        'results': [for (final r in results) searchResultJson(r)],
      }),
    );
  } else if (results.isEmpty) {
    out('No results.');
  } else {
    for (var i = 0; i < results.length; i++) {
      out('${i + 1}. ${describeSearchResult(results[i])}');
    }
  }
  return 0;
}
