import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/src/util.dart';

class LockException implements Exception {
  LockException(this.message);
  final String message;
  @override
  String toString() => 'LockException: $message';
}

/// One locked raw input: exactly which bytes were used and where they came
/// from. The cache file name embeds the hash so a new fetch never overwrites
/// the previous (known good) file.
class LockEntry {
  const LockEntry({
    required this.sourceId,
    required this.file,
    required this.sha256,
    required this.bytes,
    required this.records,
    required this.retrievedAt,
    required this.requestSha256,
    required this.endpoint,
    required this.license,
    this.sourceVersion,
  });

  factory LockEntry.fromJson(String id, Object? j) {
    if (j is! Map) throw LockException('entry "$id" is not an object');
    T need<T>(String k) {
      final v = j[k];
      if (v is! T) throw LockException('entry "$id": "$k" missing/invalid');
      return v;
    }

    return LockEntry(
      sourceId: id,
      file: need<String>('file'),
      sha256: need<String>('sha256'),
      bytes: need<int>('bytes'),
      records: need<int>('records'),
      retrievedAt: need<String>('retrieved_at'),
      requestSha256: need<String>('request_sha256'),
      endpoint: need<String>('endpoint'),
      license: need<String>('license'),
      sourceVersion: j['source_version'] as String?,
    );
  }

  final String sourceId;

  /// File name inside the cache directory.
  final String file;
  final String sha256;
  final int bytes;

  /// Record count used by the shrink guard (OSM elements / SPARQL rows).
  final int records;

  /// UTC ISO-8601 time of the fetch.
  final String retrievedAt;

  /// sha256 of the query text; a changed query makes the cache stale.
  final String requestSha256;
  final String endpoint;
  final String license;

  /// Upstream data version (OSM `timestamp_osm_base`), when the source has one.
  final String? sourceVersion;

  Map<String, Object?> toJson() => {
    'file': file,
    'sha256': sha256,
    'bytes': bytes,
    'records': records,
    'retrieved_at': retrievedAt,
    'request_sha256': requestSha256,
    'endpoint': endpoint,
    'license': license,
    'source_version': ?sourceVersion,
  };
}

/// `data/cache/sources.lock.json`: the committed record of the raw inputs.
class SourceLock {
  const SourceLock(this.entries);

  static const empty = SourceLock({});
  static const currentVersion = 1;

  final Map<String, LockEntry> entries;

  LockEntry? operator [](String id) => entries[id];

  /// Latest retrieval time; the dataset's deterministic `built_at`.
  String? get latestRetrievedAt {
    if (entries.isEmpty) return null;
    final all = entries.values.map((e) => e.retrievedAt).toList()..sort();
    return all.last;
  }

  SourceLock withEntries(Map<String, LockEntry> updates) =>
      SourceLock({...entries, ...updates});

  String encode() => canonicalJson({
    'lock_version': currentVersion,
    'sources': {for (final e in entries.entries) e.key: e.value.toJson()},
  });

  // A named static entry point reads better than a factory constructor here.
  // ignore: prefer_constructors_over_static_methods
  static SourceLock decode(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException catch (e) {
      throw LockException('lock file is not valid JSON: ${e.message}');
    }
    if (j is! Map || j['lock_version'] != currentVersion) {
      throw LockException('unsupported lock file (lock_version)');
    }
    final sources = j['sources'];
    if (sources is! Map) throw LockException('lock file has no "sources"');
    return SourceLock({
      for (final e in sources.entries)
        '${e.key}': LockEntry.fromJson('${e.key}', e.value),
    });
  }

  /// Reads [path]; a missing file is an empty lock, a corrupt one an error.
  static SourceLock read(String path) {
    final f = File(path);
    return f.existsSync() ? SourceLock.decode(f.readAsStringSync()) : empty;
  }

  /// Atomic write (temp file + rename).
  void write(String path) {
    final tmp = File('$path.tmp');
    tmp.parent.createSync(recursive: true);
    tmp.writeAsStringSync(encode());
    tmp.renameSync(path);
  }
}

/// Raw-data cache directory plus the lock that describes it.
class RawCache {
  RawCache(this.dir, this.lockPath);

  final String dir;
  final String lockPath;

  SourceLock readLock() => SourceLock.read(lockPath);

  /// Bytes of a locked file, verified against the lock. Throws
  /// [LockException] if the file is missing, truncated or modified.
  List<int> read(LockEntry e) {
    final f = File('$dir/${e.file}');
    if (!f.existsSync()) {
      throw LockException(
        '${e.sourceId}: cached file ${e.file} is missing; run `fetch`',
      );
    }
    final bytes = f.readAsBytesSync();
    if (bytes.length != e.bytes || sha256Hex(bytes) != e.sha256) {
      throw LockException(
        '${e.sourceId}: cached file ${e.file} does not match the lock '
        '(corrupted or edited); run `fetch`',
      );
    }
    return bytes;
  }
}
