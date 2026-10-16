import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:data_pipeline/src/config.dart';
import 'package:data_pipeline/src/lock.dart';
import 'package:data_pipeline/src/util.dart';

class HttpRequest {
  const HttpRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;
}

class HttpResponse {
  const HttpResponse(this.status, this.bytes, [this.headers = const {}]);

  final int status;
  final List<int> bytes;

  /// Lower-case header names.
  final Map<String, String> headers;
}

/// Network seam: the real implementation uses dart:io, tests inject a fake.
abstract interface class HttpTransport {
  Future<HttpResponse> send(HttpRequest request);
}

class IoHttpTransport implements HttpTransport {
  IoHttpTransport({this.timeout = const Duration(seconds: 150)});

  final Duration timeout;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.openUrl(request.method, request.url);
      request.headers.forEach(req.headers.set);
      if (request.body != null) req.add(utf8.encode(request.body!));
      final res = await req.close().timeout(timeout);
      final bytes = await res
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          .timeout(timeout);
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(', '));
      return HttpResponse(res.statusCode, bytes, headers);
    } finally {
      client.close(force: true);
    }
  }
}

/// A payload that must not be used (corrupt, partial, error page, ...).
class PayloadException implements Exception {
  PayloadException(this.reason);
  final String reason;
  @override
  String toString() => 'PayloadException: $reason';
}

class FetchException implements Exception {
  FetchException(this.sourceId, this.message);
  final String sourceId;
  final String message;
  @override
  String toString() => 'FetchException($sourceId): $message';
}

class PayloadInfo {
  const PayloadInfo(this.records, this.sourceVersion);
  final int records;
  final String? sourceVersion;
}

Object? _decodeJson(List<int> bytes) {
  if (bytes.isEmpty) throw PayloadException('empty response');
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    throw PayloadException(
      'not valid JSON (truncated or an error page): ${e.message}',
    );
  }
}

/// Accepts only a complete Overpass JSON answer. Overpass reports a timeout or
/// out-of-memory with HTTP 200 and a `remark` next to *partial* elements; such
/// answers are rejected.
PayloadInfo checkOverpassPayload(List<int> bytes) {
  final j = _decodeJson(bytes);
  if (j is! Map) throw PayloadException('top level is not an object');
  final remark = j['remark'];
  if (remark != null) {
    throw PayloadException('Overpass remark (partial result?): $remark');
  }
  final elements = j['elements'];
  if (elements is! List) throw PayloadException('no "elements" array');
  final osm3s = j['osm3s'];
  final version = osm3s is Map ? osm3s['timestamp_osm_base'] : null;
  if (version is! String) {
    throw PayloadException('missing osm3s.timestamp_osm_base');
  }
  return PayloadInfo(elements.length, version);
}

PayloadInfo checkSparqlPayload(List<int> bytes) {
  final j = _decodeJson(bytes);
  if (j is! Map) throw PayloadException('top level is not an object');
  final results = j['results'];
  final bindings = results is Map ? results['bindings'] : null;
  if (bindings is! List) throw PayloadException('no results.bindings array');
  return PayloadInfo(bindings.length, null);
}

typedef Sleeper = Future<void> Function(Duration);

/// Fetches every remote source into the cache, all-or-nothing.
///
/// Safety rules (docs: M2 "safe failure handling"):
/// - nothing on disk changes unless *every* source passes validation;
/// - cache files are content-addressed, so the previous good file is never
///   overwritten; the lock is rewritten last, atomically;
/// - requests are sequential, identify themselves, honour `Retry-After`,
///   back off exponentially and wait for a free Overpass slot;
/// - an answer much smaller than the previous one is refused.
class Fetcher {
  Fetcher({
    required this.transport,
    required this.settings,
    required this.userAgent,
    DateTime Function()? now,
    Sleeper? sleep,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _sleep = sleep ?? Future<void>.delayed;

  final HttpTransport transport;
  final FetchSettings settings;
  final String userAgent;
  final DateTime Function() _now;
  final Sleeper _sleep;

  Future<SourceLock> fetchAll(
    PipelineConfig config, {
    required RawCache cache,
    bool acceptShrink = false,
    Set<String>? only,
    void Function(String)? log,
  }) async {
    final previous = cache.readLock();
    final staged = <String, (LockEntry, List<int>)>{};
    for (final source in config.remote) {
      if (only != null && !only.contains(source.id)) continue;
      log?.call('fetching ${source.id} ...');
      final (bytes, info, endpoint) = await _fetchOne(source);
      final entry = LockEntry(
        sourceId: source.id,
        file: '${source.id}.${sha256Hex(bytes).substring(0, 12)}.json',
        sha256: sha256Hex(bytes),
        bytes: bytes.length,
        records: info.records,
        retrievedAt: _isoUtc(_now()),
        requestSha256: sha256Hex(utf8.encode(source.query)),
        endpoint: endpoint,
        license: source.license,
        sourceVersion: info.sourceVersion,
      );
      if (info.records < source.minRecords) {
        throw FetchException(
          source.id,
          'only ${info.records} records (minimum ${source.minRecords}); '
          'refusing to replace the cached data',
        );
      }
      final old = previous[source.id];
      if (!acceptShrink &&
          old != null &&
          old.records > 0 &&
          info.records < old.records * settings.minShrinkRatio) {
        throw FetchException(
          source.id,
          'shrank from ${old.records} to ${info.records} records '
          '(< ${settings.minShrinkRatio}); use --accept-shrink if intended',
        );
      }
      staged[source.id] = (entry, bytes);
    }

    // Commit: files first (new names), lock last, then drop superseded files.
    Directory(cache.dir).createSync(recursive: true);
    for (final (entry, bytes) in staged.values) {
      final target = File('${cache.dir}/${entry.file}');
      if (target.existsSync()) continue;
      final tmp = File('${target.path}.part')..writeAsBytesSync(bytes);
      tmp.renameSync(target.path);
    }
    final lock = previous.withEntries({
      for (final e in staged.entries) e.key: e.value.$1,
    });
    lock.write(cache.lockPath);
    final keep = {for (final e in lock.entries.values) e.file};
    for (final entry in previous.entries.values) {
      if (!keep.contains(entry.file)) {
        final f = File('${cache.dir}/${entry.file}');
        if (f.existsSync()) f.deleteSync();
      }
    }
    return lock;
  }

  Future<(List<int>, PayloadInfo, String)> _fetchOne(RemoteSource s) async {
    Object? lastError;
    Duration? retryAfter;
    for (var attempt = 1; attempt <= settings.maxAttempts; attempt++) {
      for (final endpoint in s.endpoints) {
        try {
          if (s.kind == RemoteKind.overpass) await _waitForSlot(s.id, endpoint);
          final res = await transport.send(_request(s, endpoint));
          if (res.status == 200) {
            _checkLength(res);
            final info = s.kind == RemoteKind.overpass
                ? checkOverpassPayload(res.bytes)
                : checkSparqlPayload(res.bytes);
            return (res.bytes, info, endpoint);
          }
          if (!_retryable(res.status)) {
            throw FetchException(s.id, 'HTTP ${res.status} from $endpoint');
          }
          lastError = 'HTTP ${res.status} from $endpoint';
          retryAfter = _retryAfter(res) ?? retryAfter;
        } on PayloadException catch (e) {
          lastError = '$endpoint: ${e.reason}';
        } on SocketException catch (e) {
          lastError = '$endpoint: ${e.message}';
        } on HttpException catch (e) {
          lastError = '$endpoint: ${e.message}';
        } on TimeoutException {
          lastError = '$endpoint: timed out';
        } on TlsException catch (e) {
          lastError = '$endpoint: ${e.message}';
        }
      }
      if (attempt < settings.maxAttempts) {
        await _sleep(_backoff(attempt, retryAfter));
        retryAfter = null;
      }
    }
    throw FetchException(
      s.id,
      'failed after ${settings.maxAttempts} attempt(s); last error: $lastError. '
      'Cached data was left untouched.',
    );
  }

  HttpRequest _request(RemoteSource s, String endpoint) {
    final field = s.kind == RemoteKind.overpass ? 'data' : 'query';
    return HttpRequest(
      method: 'POST',
      url: Uri.parse(endpoint),
      headers: {
        'User-Agent': userAgent,
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        'Accept': s.kind == RemoteKind.overpass
            ? 'application/json'
            : 'application/sparql-results+json',
      },
      body: '$field=${Uri.encodeQueryComponent(s.query)}',
    );
  }

  void _checkLength(HttpResponse res) {
    // Content-Length counts the *encoded* body; dart:io decompresses before we
    // see the bytes, so the sizes only compare when nothing was encoded.
    final encoding = res.headers['content-encoding'];
    if (encoding != null && encoding.isNotEmpty && encoding != 'identity') {
      return;
    }
    final declared = int.tryParse(res.headers['content-length'] ?? '');
    if (declared != null && declared != res.bytes.length) {
      throw PayloadException(
        'incomplete download: got ${res.bytes.length} of $declared bytes',
      );
    }
  }

  bool _retryable(int status) =>
      status == 429 || status == 502 || status == 503 || status == 504;

  Duration? _retryAfter(HttpResponse res) {
    final secs = int.tryParse(res.headers['retry-after'] ?? '');
    return secs == null ? null : Duration(seconds: secs);
  }

  Duration _backoff(int attempt, Duration? retryAfter) {
    final exp = settings.baseDelay * (1 << (attempt - 1));
    final wait = exp > settings.maxDelay ? settings.maxDelay : exp;
    if (retryAfter == null) return wait;
    return retryAfter > wait ? retryAfter : wait;
  }

  /// Respects the Overpass slot limit: ask `/api/status` and wait for a free
  /// slot instead of firing a query that would be rejected.
  Future<void> _waitForSlot(String sourceId, String endpoint) async {
    final statusUrl = endpoint.replaceFirst(
      RegExp(r'interpreter/?$'),
      'status',
    );
    if (statusUrl == endpoint) return;
    final String text;
    try {
      final res = await transport.send(
        HttpRequest(
          method: 'GET',
          url: Uri.parse(statusUrl),
          headers: {'User-Agent': userAgent},
        ),
      );
      if (res.status != 200) return; // best effort only
      text = utf8.decode(res.bytes, allowMalformed: true);
    } on Object {
      return; // status is advisory; the real request reports real failures
    }
    final slots = RegExp(r'(\d+) slots? available now').firstMatch(text);
    if (slots != null && int.parse(slots.group(1)!) > 0) return;
    final wait = RegExp(r'in (\d+) seconds').firstMatch(text);
    if (wait == null) return;
    final delay = Duration(seconds: int.parse(wait.group(1)!) + 1);
    if (delay > settings.maxSlotWait) {
      throw FetchException(
        sourceId,
        'Overpass has no free slot for ${delay.inSeconds}s '
        '(limit ${settings.maxSlotWait.inSeconds}s); try later',
      );
    }
    await _sleep(delay);
  }

  static String _isoUtc(DateTime t) =>
      '${t.toUtc().toIso8601String().split('.').first}Z';
}
