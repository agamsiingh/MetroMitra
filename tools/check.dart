// One command to verify the repo: `dart run tools/check.dart`
//
// Steps: l10n codegen, format, analyze, tests (all packages), fixture
// validation + build, secrets scan, metro_core purity. Pass --fast to skip tests. Exits non-zero on first failure.
import 'dart:convert';
import 'dart:io';

import 'check_secrets.dart' as secrets;

const _dartPackages = [
  'packages/metro_core',
  'server/ai-proxy',
  'tools/data_pipeline',
];
const _formatTargets = [
  'app/lib',
  'app/test',
  'packages/metro_core/lib',
  'packages/metro_core/test',
  'server',
  'tools',
];

Future<void> main(List<String> args) async {
  final fast = args.contains('--fast');

  await _step('flutter gen-l10n', 'flutter', ['gen-l10n'], dir: 'app');
  await _step('format', 'dart', [
    'format',
    '--output=none',
    '--set-exit-if-changed',
    ..._formatTargets,
  ]);
  await _step('analyze app', 'flutter', ['analyze'], dir: 'app');
  for (final pkg in _dartPackages) {
    await _step('analyze $pkg', 'dart', ['analyze'], dir: pkg);
  }
  if (!fast) {
    await _step('test app', 'flutter', ['test'], dir: 'app');
    for (final pkg in _dartPackages) {
      await _step('test $pkg', 'dart', ['test'], dir: pkg);
    }
  }
  // admin panel (Node): only when its dependencies are installed
  if (Directory('admin/node_modules').existsSync()) {
    await _step('admin typecheck', 'npm', ['run', 'typecheck'], dir: 'admin');
    if (!fast) await _step('admin tests', 'npm', ['test'], dir: 'admin');
  } else {
    _section('admin checks skipped (run `npm install` in admin/)');
  }
  _section('dataset validation (test fixture + pipeline build)');
  await _step('validate fixture', 'dart', [
    'run',
    'tools/data_pipeline/bin/build.dart',
    'validate',
  ]);
  await _step('build fixture', 'dart', [
    'run',
    'tools/data_pipeline/bin/build.dart',
    'build',
    '--input',
    'data/fixtures/mini_network/dataset.yaml',
    '--allow-test-data',
    '--out',
    'build/pipeline/fixture.sqlite',
  ]);
  if (File('data/cache/sources.lock.json').existsSync()) {
    await _step('offline build from the locked cache', 'dart', [
      'run',
      'tools/data_pipeline/bin/build.dart',
      'build',
      '--offline',
      '--out',
      'build/pipeline/check.sqlite',
      '--report',
      'build/pipeline/check-report.json',
    ]);
    _section('real-data guards (curation, connectivity, search)');
    if (!_realDataGuards('build/pipeline/check-report.json')) {
      _fail('real-data guards');
    }
    // official per-line station counts (data/curated/reference)
    await _step('reference check (official DMRC figures)', 'dart', [
      'run',
      'tools/data_pipeline/bin/build.dart',
      'reference',
      '--input',
      'build/pipeline/check.sqlite',
    ]);
  } else {
    _section('offline build skipped (no data/cache/sources.lock.json)');
  }
  _section('bundled dataset is release-only');
  if (!_bundledDatasetIsRelease()) _fail('bundled dataset is release-only');
  _section('secrets scan');
  if (secrets.main() != 0) _fail('secrets scan');
  _section('metro_core purity');
  if (!_corePure()) _fail('metro_core purity');

  stdout.writeln('\nAll checks passed.');
}

/// Regression guards on the real (draft) build: every same-name interchange
/// candidate is curated, the routing graph is one connected network, and
/// every station can be found by its own names and codes.
bool _realDataGuards(String reportPath) {
  final report =
      jsonDecode(File(reportPath).readAsStringSync()) as Map<String, Object?>;
  final byKind = ((report['conflicts']! as Map)['by_kind']! as Map)
      .cast<String, int>();
  final routing = report['routing']! as Map;
  var ok = true;
  final open = byKind['interchange-candidate'] ?? 0;
  if (open > 0) {
    stderr.writeln('$open interchange candidate(s) are not curated');
    ok = false;
  }
  if (routing['components'] != 1) {
    stderr.writeln(
      'routing graph has ${routing['components']} parts: '
      '${routing['smaller_components']}',
    );
    ok = false;
  }
  final search = report['search']! as Map;
  if (search['self_check_problems'] != 0) {
    stderr.writeln(
      'search self-check: ${search['self_check_problems']} problem(s): '
      '${search['self_check_examples']}',
    );
    ok = false;
  }
  if (ok) stdout.writeln('ok (stage ${report['stage']})');
  return ok;
}

/// A draft (or any) dataset must never ship inside the app assets.
/// Only `app/assets/data/metro.sqlite` may be bundled, and only when it passes
/// release validation (never a draft or test dataset).
bool _bundledDatasetIsRelease() {
  final dir = Directory('app/assets/data');
  final found = [
    if (dir.existsSync())
      for (final f in dir.listSync(recursive: true))
        if (f is File && RegExp(r'\.(sqlite|db|json)$').hasMatch(f.path))
          f.path.replaceAll(r'\', '/'),
  ];
  if (found.isEmpty) {
    stdout.writeln('ok (nothing bundled)');
    return true;
  }
  if (found.length != 1 || !found.single.endsWith('/metro.sqlite')) {
    stderr.writeln('unexpected dataset files in app assets: $found');
    return false;
  }
  final r = Process.runSync('dart', [
    'run',
    'tools/data_pipeline/bin/build.dart',
    'validate',
    '--input',
    found.single,
  ], runInShell: true);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) {
    stderr.writeln('bundled dataset is not a valid release dataset');
    return false;
  }
  // validate checks structure only; stage and test-data live in meta.
  final m = Process.runSync('dart', [
    'run',
    'tools/data_pipeline/bin/build.dart',
    'inspect',
    '--input',
    found.single,
    '--table',
    'meta',
  ], runInShell: true);
  final meta = <String, Object?>{
    for (final line in '${m.stdout}'.split('\n'))
      if (line.trim().startsWith('{'))
        if (jsonDecode(line) case {'key': final String k, 'value': final v})
          k: v,
  };
  if (m.exitCode != 0 ||
      meta['stage'] != 'release' ||
      meta.keys.any((k) => k.contains('test'))) {
    stderr.writeln(
      'bundled dataset must be stage "release" and not test data: $meta',
    );
    return false;
  }
  stdout.writeln('ok (release dataset ${meta['dataset_version']})');
  return true;
}

/// metro_core must stay pure Dart: no Flutter, no platform plugins, no HTTP.
bool _corePure() {
  final forbidden = RegExp(
    r'''import\s+['"]package:(flutter|flutter_[a-z_]+|http|dio|drift|geolocator|url_launcher|wakelock_plus|in_app_[a-z_]+|google_mobile_ads)\b''',
  );
  var ok = true;
  final pubspec = File('packages/metro_core/pubspec.yaml').readAsStringSync();
  if (RegExp(r'^\s*flutter\s*:', multiLine: true).hasMatch(pubspec)) {
    stderr.writeln('packages/metro_core/pubspec.yaml depends on flutter');
    ok = false;
  }
  for (final f in Directory(
    'packages/metro_core/lib',
  ).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (forbidden.hasMatch(lines[i])) {
        stderr.writeln('${f.path}:${i + 1}: forbidden import in metro_core');
        ok = false;
      }
    }
  }
  if (ok) stdout.writeln('ok');
  return ok;
}

void _section(String name) => stdout.writeln('\n== $name');

Never _fail(String name) {
  stderr.writeln('\nFAILED: $name');
  exit(1);
}

Future<void> _step(
  String name,
  String exe,
  List<String> args, {
  String dir = '.',
}) async {
  _section(name);
  final process = await Process.start(
    exe,
    args,
    workingDirectory: dir,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  if (await process.exitCode != 0) _fail(name);
}
