import 'dart:io';

import 'package:yaml/yaml.dart';

/// Raised for unusable pipeline configuration (missing/invalid files).
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => 'ConfigException: $message';
}

enum RemoteKind { overpass, sparql }

/// A source fetched over the network.
class RemoteSource {
  const RemoteSource({
    required this.id,
    required this.kind,
    required this.name,
    required this.license,
    required this.licenseUrl,
    required this.attribution,
    required this.endpoints,
    required this.query,
    required this.queryFile,
    required this.minRecords,
    this.network,
  });

  final String id;
  final RemoteKind kind;
  final String name;
  final String license;
  final String licenseUrl;
  final String attribution;

  /// Tried in order; the first that answers wins.
  final List<String> endpoints;

  /// Query text (read from [queryFile]).
  final String query;
  final String queryFile;
  final int minRecords;

  /// Overpass only: relation `network` tag to keep.
  final String? network;
}

class LocalSource {
  const LocalSource({
    required this.id,
    required this.name,
    required this.license,
    required this.notes,
  });

  final String id;
  final String name;
  final String license;
  final String notes;
}

class FetchSettings {
  const FetchSettings({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(minutes: 5),
    this.maxSlotWait = const Duration(minutes: 2),
    this.requestTimeout = const Duration(seconds: 150),
    this.minShrinkRatio = 0.5,
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Duration maxSlotWait;
  final Duration requestTimeout;
  final double minShrinkRatio;
}

class NormalizationRules {
  const NormalizationRules({
    this.stripSuffixesEn = const [],
    this.stripSuffixesHi = const [],
    this.candidateStripPattern,
  });

  /// Removed from a name only when *comparing* stations across lines (e.g. a
  /// trailing "(Pink Line)"); display names are never changed by it.
  final String? candidateStripPattern;

  final List<String> stripSuffixesEn;
  final List<String> stripSuffixesHi;
}

class PipelineConfig {
  const PipelineConfig({
    required this.city,
    required this.bbox,
    required this.maxClusterSpreadM,
    required this.coordinateConflictM,
    required this.mergeCandidateRadiusM,
    required this.curatedOverlayPath,
    required this.fetch,
    required this.remote,
    required this.local,
    required this.normalization,
  });

  final String city;
  final String bbox;
  final double maxClusterSpreadM;
  final double coordinateConflictM;
  final double mergeCandidateRadiusM;
  final String curatedOverlayPath;
  final FetchSettings fetch;
  final List<RemoteSource> remote;
  final List<LocalSource> local;
  final NormalizationRules normalization;

  RemoteSource remoteById(String id) => remote.firstWhere(
    (r) => r.id == id,
    orElse: () => throw ConfigException('No remote source "$id" configured'),
  );

  /// Loads `sources.yaml`; relative paths (queries, overlay) resolve against
  /// [root] (the repository root).
  // A named static entry point reads better than a factory constructor here.
  // ignore: prefer_constructors_over_static_methods
  static PipelineConfig load(String path, {String root = '.'}) {
    final file = File(path);
    if (!file.existsSync()) throw ConfigException('Missing config $path');
    final Object? doc;
    try {
      doc = loadYaml(file.readAsStringSync());
    } on YamlException catch (e) {
      throw ConfigException('$path: ${e.message}');
    }
    if (doc is! YamlMap) throw ConfigException('$path: must be a map');

    YamlMap map(Object? v, String what) => v is YamlMap
        ? v
        : throw ConfigException('$path: "$what" must be a map');
    T req<T>(YamlMap m, String key, String where) {
      final v = m[key];
      if (v is! T) {
        throw ConfigException('$path: $where.$key missing or wrong type');
      }
      return v;
    }

    final ds = map(doc['dataset'], 'dataset');
    final fetch = doc['fetch'] == null ? null : map(doc['fetch'], 'fetch');
    Duration secs(String key, Duration fallback) {
      final v = fetch?[key];
      return v is num ? Duration(seconds: v.toInt()) : fallback;
    }

    String readQuery(String rel) {
      final f = File('$root/$rel');
      if (!f.existsSync()) throw ConfigException('Missing query file $rel');
      return f.readAsStringSync();
    }

    final remote = <RemoteSource>[];
    for (final r in (doc['remote'] as YamlList? ?? YamlList())) {
      final m = map(r, 'remote[]');
      final id = req<String>(m, 'id', 'remote');
      final kind = switch (req<String>(m, 'kind', id)) {
        'overpass' => RemoteKind.overpass,
        'sparql' => RemoteKind.sparql,
        final other => throw ConfigException('$path: $id: unknown kind $other'),
      };
      final endpoints = kind == RemoteKind.overpass
          ? [for (final e in req<YamlList>(m, 'endpoints', id)) '$e']
          : [req<String>(m, 'endpoint', id)];
      final queryFile = req<String>(m, 'query_file', id);
      remote.add(
        RemoteSource(
          id: id,
          kind: kind,
          name: req<String>(m, 'name', id),
          license: req<String>(m, 'license', id),
          licenseUrl: req<String>(m, 'license_url', id),
          attribution: req<String>(m, 'attribution', id),
          endpoints: endpoints,
          query: readQuery(queryFile),
          queryFile: queryFile,
          minRecords: (m['min_records'] as int?) ?? 1,
          network: m['network'] as String?,
        ),
      );
    }
    if (remote.map((r) => r.id).toSet().length != remote.length) {
      throw ConfigException('$path: duplicate remote source ids');
    }

    final local = [
      for (final l in (doc['local'] as YamlList? ?? YamlList()))
        LocalSource(
          id: req<String>(map(l, 'local[]'), 'id', 'local'),
          name: req<String>(l as YamlMap, 'name', 'local'),
          license: req<String>(l, 'license', 'local'),
          notes: (l['notes'] as String?) ?? '',
        ),
    ];

    final norm = doc['normalization'] == null
        ? null
        : map(doc['normalization'], 'normalization');
    List<String> list(String key) => [
      for (final s in (norm?[key] as YamlList? ?? YamlList())) '$s',
    ];

    return PipelineConfig(
      city: req<String>(ds, 'city', 'dataset'),
      bbox: req<String>(ds, 'bbox', 'dataset'),
      maxClusterSpreadM: (ds['max_cluster_spread_m'] as num? ?? 800).toDouble(),
      coordinateConflictM: (ds['coordinate_conflict_m'] as num? ?? 250)
          .toDouble(),
      mergeCandidateRadiusM: (ds['merge_candidate_radius_m'] as num? ?? 500)
          .toDouble(),
      curatedOverlayPath: req<String>(ds, 'curated_overlay', 'dataset'),
      fetch: FetchSettings(
        maxAttempts: (fetch?['max_attempts'] as int?) ?? 3,
        baseDelay: secs('base_delay_s', const Duration(seconds: 30)),
        maxDelay: secs('max_delay_s', const Duration(minutes: 5)),
        maxSlotWait: secs('max_slot_wait_s', const Duration(minutes: 2)),
        requestTimeout: secs('request_timeout_s', const Duration(seconds: 150)),
        minShrinkRatio: (fetch?['min_shrink_ratio'] as num? ?? 0.5).toDouble(),
      ),
      remote: remote,
      local: local,
      normalization: NormalizationRules(
        stripSuffixesEn: list('strip_suffixes_en'),
        stripSuffixesHi: list('strip_suffixes_hi'),
        candidateStripPattern: norm?['candidate_strip_pattern'] as String?,
      ),
    );
  }
}
