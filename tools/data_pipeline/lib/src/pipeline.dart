import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/src/admin_import.dart';
import 'package:data_pipeline/src/config.dart';
import 'package:data_pipeline/src/conflict.dart';
import 'package:data_pipeline/src/lock.dart';
import 'package:data_pipeline/src/merge.dart';
import 'package:data_pipeline/src/normalize.dart';
import 'package:data_pipeline/src/overlay.dart';
import 'package:data_pipeline/src/route_report.dart';
import 'package:data_pipeline/src/search_report.dart';
import 'package:data_pipeline/src/util.dart';
import 'package:metro_core/metro_core.dart';

/// Pipeline version recorded in reports (not in the dataset).
const pipelineVersion = '0.2.0';

/// Joins [path] onto [root] unless it is already absolute.
String resolvePath(String root, String path) =>
    (File(path).isAbsolute || path.startsWith('/')) ? path : '$root/$path';

class BuildPaths {
  const BuildPaths({
    this.root = '.',
    this.config = 'data/sources/sources.yaml',
    this.cacheDir = 'data/cache',
    this.lock = 'data/cache/sources.lock.json',
    this.out = 'build/pipeline/metro.sqlite',
    this.report = 'build/pipeline/build-report.json',
    this.adminExport = 'data/curated/admin-approved.json',
  });

  final String root;
  final String config;
  final String cacheDir;
  final String lock;
  final String out;
  final String report;

  /// Approved rows exported from the admin panel; optional.
  final String adminExport;
}

/// Why a build could not even start (missing/stale/corrupt inputs).
class InputException implements Exception {
  InputException(this.message);
  final String message;
  @override
  String toString() => 'InputException: $message';
}

class BuildOutcome {
  const BuildOutcome({
    required this.ok,
    required this.stage,
    required this.report,
    required this.conflicts,
    this.snapshot,
    this.outputSha256,
  });

  /// A sqlite file was written.
  final bool ok;

  /// `release`, `draft`, or `failed`.
  final String stage;
  final Map<String, Object?> report;
  final List<Conflict> conflicts;
  final MetroSnapshot? snapshot;
  final String? outputSha256;
}

/// SOURCE DATA -> NORMALIZATION -> CURATED OVERLAYS -> CONFLICT CHECK ->
/// CANONICAL DATASET -> VALIDATION -> SQLITE. Fully offline: reads only the
/// locked cache, the overlay and the config, so identical inputs give an
/// identical file.
BuildOutcome buildDataset(
  BuildPaths p, {
  bool requireRelease = false,
  DateTime? now,
  void Function(String)? log,
}) {
  final config = PipelineConfig.load(
    resolvePath(p.root, p.config),
    root: p.root,
  );
  final cache = RawCache(
    resolvePath(p.root, p.cacheDir),
    resolvePath(p.root, p.lock),
  );
  final lock = cache.readLock();

  final raw = <String, List<int>>{};
  for (final source in config.remote) {
    final entry = lock[source.id];
    if (entry == null) {
      throw InputException(
        'No cached data for "${source.id}". Run `fetch` first '
        '(or restore data/cache from the release archive).',
      );
    }
    if (entry.requestSha256 != sha256Hex(utf8.encode(source.query))) {
      throw InputException(
        '"${source.id}": the query file changed since the cache was fetched; '
        'run `fetch` to refresh the lock.',
      );
    }
    try {
      raw[source.id] = cache.read(entry);
    } on LockException catch (e) {
      throw InputException(e.message);
    }
  }

  log?.call('normalizing ...');
  final osmSource = config.remoteById(osmSourceId);
  final osm = normalizeOsm(raw[osmSourceId]!, network: osmSource.network ?? '');
  final wd = config.remote.any((r) => r.id == wikidataSourceId)
      ? normalizeWikidata(raw[wikidataSourceId]!, config.normalization)
      : null;
  final fileOverlay = Overlay.load(
    resolvePath(p.root, config.curatedOverlayPath),
  );
  final admin = AdminImport.load(resolvePath(p.root, p.adminExport));
  // Admin rows are applied after the YAML overlay, so for the same field the
  // admin value wins; both are listed in the overrides report.
  final overlay = Overlay(
    patch: fileOverlay.patch,
    operators: fileOverlay.operators,
    lines: fileOverlay.lines,
    stations: [...fileOverlay.stations, ...admin.stations],
    merges: fileOverlay.merges,
    resolutions: fileOverlay.resolutions,
    // the curated provenance hash covers both inputs
    sha256: admin.file == null
        ? fileOverlay.sha256
        : sha256Hex(utf8.encode('${fileOverlay.sha256}+${admin.sha256}')),
  );

  log?.call('merging ...');
  final merged = mergeSources(
    osm: osm,
    wikidata: wd,
    overlay: overlay,
    config: config,
    lock: lock,
  );

  // Validation: release rules first, then the draft profile.
  final releaseReport = validateSnapshot(merged.snapshot, now: now);
  final draftReport = validateSnapshot(
    merged.snapshot,
    now: now,
    mode: ValidationMode.draft,
  );
  final blocking = merged.blocking;
  final canWrite = blocking.isEmpty && draftReport.isValid;
  final stage = !canWrite
      ? 'failed'
      : releaseReport.isValid
      ? 'release'
      : 'draft';

  String? outSha;
  MetroSnapshot? outSnapshot;
  final outPath = resolvePath(p.root, p.out);
  if (canWrite && !(requireRelease && stage != 'release')) {
    final snapshot = merged.snapshot.copyWith(
      meta: {...merged.snapshot.meta, MetaKeys.stage: stage},
    );
    DatasetWriter.writeFile(snapshot, outPath);
    // Re-read what was written, exactly as the device would.
    outSnapshot = DatasetReader.readFile(
      outPath,
      mode: stage == 'draft' ? ValidationMode.draft : ValidationMode.release,
    );
    outSha = sha256Hex(File(outPath).readAsBytesSync());
  }

  final report = <String, Object?>{
    'pipeline': {
      'name': 'metromitra-data-pipeline',
      'version': pipelineVersion,
    },
    'stage': stage,
    'inputs': {
      for (final s in config.remote)
        s.id: {
          ...lock[s.id]!.toJson(),
          'license_url': s.licenseUrl,
          'attribution': s.attribution,
        },
      'curated-overlay': {
        'file': config.curatedOverlayPath,
        'sha256': fileOverlay.sha256,
        'operators': overlay.operators.length,
        'lines': overlay.lines.length,
        'stations': overlay.stations.length,
        'station_merges': overlay.merges.length,
        'resolutions': overlay.resolutions.length,
      },
      if (admin.file != null)
        'admin-export': {
          'file': p.adminExport,
          'sha256': admin.sha256,
          'stations': admin.stations.length,
          'not_imported_yet': admin.notImported,
        },
    },
    'dataset': {
      'dataset_version': merged.snapshot.datasetVersion,
      'schema_version': merged.snapshot.schemaVersion,
      'built_at': merged.snapshot.meta[MetaKeys.builtAt],
      ...merged.stats,
    },
    'validation': {
      'release': _validationJson(releaseReport),
      'draft': _validationJson(draftReport),
    },
    'conflicts': {
      'total': merged.conflicts.length,
      'blocking': blocking.length,
      'by_kind': _countBy(merged.conflicts.map((c) => c.kind)),
      'items': [for (final c in merged.conflicts) c.toJson()],
    },
    'overrides': [for (final o in merged.overrides) o.toJson()],
    'routing': routingReport(merged.snapshot, const TravelTimeModel()),
    'search': searchReport(merged.snapshot),
    'output': canWrite && outSha != null
        ? {
            'file': p.out,
            'sha256': outSha,
            'bytes': File(outPath).lengthSync(),
          }
        : null,
  };
  File(resolvePath(p.root, p.report))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(canonicalJson(report));

  return BuildOutcome(
    ok: outSha != null,
    stage: stage,
    report: report,
    conflicts: merged.conflicts,
    snapshot: outSnapshot,
    outputSha256: outSha,
  );
}

Map<String, int> _countBy(Iterable<String> values) {
  final out = <String, int>{};
  for (final v in values) {
    out[v] = (out[v] ?? 0) + 1;
  }
  return Map.fromEntries(
    out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

Map<String, Object?> _validationJson(ValidationReport r) => {
  'valid': r.isValid,
  'errors': [for (final i in r.errors) '${i.code}: ${i.message}'],
  'warning_counts': _countBy(r.warnings.map((w) => w.code)),
};
