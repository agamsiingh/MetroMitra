import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Network trouble: no connection, timeout, bad HTTP status, cut-off body.
class TransportException implements Exception {
  const TransportException(this.message);
  final String message;
  @override
  String toString() => 'TransportException: $message';
}

abstract interface class UpdateTransport {
  /// Body of the manifest (small, text).
  Future<String> fetchManifest(Uri url);

  /// Downloads [url] into [part]. If [part] already holds bytes of an earlier
  /// interrupted attempt the transfer resumes behind them when the server
  /// supports ranges, otherwise it starts again. Completes only when the body
  /// ended cleanly; verification of the content is the caller's job.
  Future<void> download(Uri url, File part, {required int maxBytes});
}

/// `dart:io` HttpClient transport: short timeouts, HTTPS only, redirects
/// followed by hand so every hop is checked.
class HttpUpdateTransport implements UpdateTransport {
  HttpUpdateTransport({
    this.connectTimeout = const Duration(seconds: 5),
    this.idleTimeout = const Duration(seconds: 15),
    this.allowInsecureLoopback = false,
    this.maxManifestBytes = 64 * 1024,
  });

  final Duration connectTimeout;

  /// Longest wait for the next piece of a response.
  final Duration idleTimeout;

  /// Tests talk to a local server over http; everything else must be https.
  final bool allowInsecureLoopback;
  final int maxManifestBytes;

  static const _maxRedirects = 3;

  bool _allowed(Uri u) =>
      u.scheme == 'https' ||
      (allowInsecureLoopback &&
          u.scheme == 'http' &&
          (u.host == '127.0.0.1' || u.host == 'localhost'));

  @override
  Future<String> fetchManifest(Uri url) async {
    final bytes = <int>[];
    await _get(url, (response) async {
      await for (final c in response.timeout(idleTimeout)) {
        bytes.addAll(c);
        if (bytes.length > maxManifestBytes) {
          throw const TransportException('manifest too large');
        }
      }
    });
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const TransportException('manifest is not text');
    }
  }

  @override
  Future<void> download(Uri url, File part, {required int maxBytes}) async {
    final have = part.existsSync() ? part.lengthSync() : 0;
    await _get(
      url,
      range: have > 0 ? have : null,
      (response) async {
        final resumed = response.statusCode == HttpStatus.partialContent;
        final sink = part.openWrite(
          mode: resumed ? FileMode.append : FileMode.write,
        );
        var total = resumed ? have : 0;
        try {
          await for (final c in response.timeout(idleTimeout)) {
            total += c.length;
            if (total > maxBytes) {
              throw const TransportException('download larger than allowed');
            }
            sink.add(c);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
        final expected = response.contentLength;
        if (expected >= 0 && total - (resumed ? have : 0) != expected) {
          throw const TransportException('download cut short');
        }
      },
    );
  }

  Future<void> _get(
    Uri url,
    Future<void> Function(HttpClientResponse) onBody, {
    int? range,
  }) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      var target = url;
      for (var hop = 0; hop <= _maxRedirects; hop++) {
        if (!_allowed(target)) {
          throw TransportException('refusing non-HTTPS address ($target)');
        }
        final request = await client.getUrl(target).timeout(connectTimeout);
        request.followRedirects = false;
        if (range != null) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$range-');
        }
        final response = await request.close().timeout(idleTimeout);
        final code = response.statusCode;
        if (code >= 300 && code < 400) {
          final loc = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (loc == null) throw const TransportException('bad redirect');
          target = target.resolve(loc);
          continue;
        }
        if (code == HttpStatus.requestedRangeNotSatisfiable) {
          await response.drain<void>();
          // the leftover bytes do not fit this file: start again
          return _get(url, onBody);
        }
        if (code != HttpStatus.ok && code != HttpStatus.partialContent) {
          await response.drain<void>();
          throw TransportException('HTTP $code');
        }
        await onBody(response);
        return;
      }
      throw const TransportException('too many redirects');
    } on TransportException {
      rethrow;
    } on TimeoutException {
      throw const TransportException('timed out');
    } on SocketException catch (e) {
      throw TransportException('network unavailable (${e.osError?.message})');
    } on HandshakeException {
      throw const TransportException('secure connection failed');
    } on HttpException catch (e) {
      throw TransportException('connection broke (${e.message})');
    } on FileSystemException {
      throw const TransportException('could not write the download');
    } finally {
      client.close(force: true);
    }
  }
}
