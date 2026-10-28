import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/network/cancellation_token.dart';
import '../../core/network/header_policy.dart';
import '../../core/network/media_http_client.dart';
import '../cache/resource_identity.dart';
import '../cache/segment_store.dart';
import '../cache/segment_fetcher.dart';
import '../cache/segment_prefetcher.dart';
import '../hls/hls_manifest.dart';
import '../hls/hls_quality.dart';
import '../hls/ad_filter.dart';
import '../hls/timeline.dart';

final class GatewaySession {
  GatewaySession._(this._gateway, this.token, this.policy);
  final MediaGateway _gateway;
  final String token;
  final HeaderPolicy policy;
  final _resources = <String, Uri>{};
  final _ids = <Uri, String>{};
  final _playlists = <Uri>{};
  final _streaming = <Uri>{};
  Uri? selectedQuality;
  List<HlsQuality> qualities = [];
  bool filterAds = false;
  bool cacheEnabled = true;
  bool _canFilterAds = true;
  final _variables = <Uri, Map<String, String>>{};
  MediaTimeline timeline = const MediaTimeline([]);
  late final prefetch = SegmentPrefetcher(
    SegmentFetcher(_gateway.store, _gateway._client),
    policy,
  );
  final cancellation = CancellationToken();
  bool _closed = false;

  Uri register(Uri uri, {bool playlist = false, bool streaming = false}) {
    if (_closed) throw StateError('Session is closed');
    if (!{'http', 'https'}.contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      throw const FormatException('Unsupported media URL');
    }
    if (_resources.length >= 20000 && !_ids.containsKey(uri)) {
      throw const FormatException('Playlist resource limit exceeded');
    }
    final id = _ids.putIfAbsent(uri, () => '${_ids.length}');
    if (playlist || uri.path.toLowerCase().endsWith('.m3u8')) {
      _playlists.add(uri);
    }
    _resources[id] = uri;
    if (streaming) _streaming.add(uri);
    return _gateway.baseUri.resolve('$token/$id');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    prefetch.close();
    cancellation.cancel();
    _resources.clear();
    _ids.clear();
    _gateway._sessions.remove(token);
  }
}

/// Capability URLs map to registered resources; there is no arbitrary URL
/// query parameter and the socket is bound exclusively to IPv4 loopback.
final class MediaGateway {
  MediaGateway(this.store, {MediaHttpClient? client})
    : _client = client ?? MediaHttpClient(),
      _ownsClient = client == null;
  final SegmentStore store;
  final MediaHttpClient _client;
  final bool _ownsClient;
  final _sessions = <String, GatewaySession>{};
  final _transfers = CancellationToken();
  HttpServer? _server;
  Future<void>? _starting;
  Future<void>? _closing;
  bool _closed = false;
  int requests = 0;
  int failures = 0;
  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server!.port}/');

  Future<void> start() {
    if (_closed) return Future.error(StateError('Gateway is closed'));
    if (_server != null) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      return;
    }
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
  }

  GatewaySession createSession(HeaderPolicy policy) {
    if (_server == null) throw StateError('Start gateway first');
    final random = Random.secure();
    final token = base64Url.encode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    final session = GatewaySession._(this, token, policy);
    _sessions[token] = session;
    return session;
  }

  Future<void> _handle(HttpRequest request) async {
    ResourceLease? lease;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      // Browsers must not turn the native player's capability URL into a
      // cross-origin fetch endpoint. Native engines do not send Origin.
      if (request.headers.value('origin') != null) {
        request.response.statusCode = HttpStatus.forbidden;
        return;
      }
      final parts = request.uri.pathSegments;
      final session = parts.length == 2 ? _sessions[parts[0]] : null;
      final uri = session?._resources[parts[1]];
      if (uri == null || session == null) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      requests++;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && !RegExp(r'^bytes=(\d+-\d*|-\d+)$').hasMatch(range)) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        return;
      }
      if (session._playlists.contains(uri)) {
        await _manifest(request, session, uri);
      } else if (!session.cacheEnabled ||
          !(await session.prefetch.prepare()) ||
          session._streaming.contains(uri) ||
          uri.path.toLowerCase().endsWith('.flv')) {
        await _passthrough(request, session, uri, range);
      } else {
        final key = resourceIdentity(
          uri,
          session.policy.identityHeaders,
          range,
        );
        try {
          lease = await store.acquire(
            key,
            () => _fetch(session, uri, range, key),
          );
        } on FileSystemException {
          await _passthrough(request, session, uri, range);
          return;
        }
        final resource = lease.resource;
        session.prefetch.observe(uri, resource.length, range: range);
        request.response.statusCode = resource.statusCode;
        resource.headers.forEach(request.response.headers.set);
        request.response.contentLength = resource.length;
        if (request.method != 'HEAD') {
          await request.response.addStream(resource.file.openRead());
        }
      }
    } catch (_) {
      failures++;
      // Never expose signed upstream URLs, headers, tokens or raw exceptions.
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('Media request failed');
      } catch (_) {
        // Client disconnected or response headers already sent.
      }
    } finally {
      lease?.release();
      try {
        await request.response.close();
      } catch (_) {
        /* Disconnected. */
      }
    }
  }

  Future<void> _passthrough(
    HttpRequest request,
    GatewaySession session,
    Uri uri,
    String? range,
  ) async {
    final payload = await _client.open(
      uri,
      policy: session.policy,
      range: range,
      cancellation: session.cancellation,
    );
    final body = StreamIterator(payload.body);
    Stream<List<int>> chunks() async* {
      while (await body.moveNext()) {
        yield body.current;
      }
    }

    try {
      request.response.statusCode = payload.response.statusCode;
      for (final name in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = payload.response.headers.value(name);
        if (value != null) request.response.headers.set(name, value);
      }
      request.response.contentLength = payload.response.contentLength;
      if (request.method != 'HEAD') await request.response.addStream(chunks());
    } finally {
      // Covers failures before addStream subscribes as well as client disconnects.
      await body.cancel();
    }
  }

  Future<void> _manifest(
    HttpRequest request,
    GatewaySession session,
    Uri uri,
  ) async {
    final payload = await _client.open(
      uri,
      policy: session.policy,
      cancellation: session.cancellation,
    );
    if (payload.response.statusCode != 200) {
      await payload.body.drain<void>();
      throw const HttpException('Manifest unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in payload.body) {
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const FormatException('Manifest exceeds 2 MiB');
      }
      bytes.addAll(chunk);
    }
    var manifest = HlsManifest.parse(
      utf8.decode(bytes),
      payload.uri,
      variables: session._variables[uri] ?? const {},
    );
    if (manifest.isMaster) {
      session.qualities = hlsQualities(manifest);
      manifest = selectHlsQuality(manifest, session.selectedQuality);
      // A single muxed rendition has one timeline. Cutting only the video of
      // an external-audio master, or unmatched adaptive renditions, desyncs it.
      session._canFilterAds =
          manifest.playlistUris.length == 1 &&
          !manifest.lines.any(
            (line) =>
                line.startsWith('#EXT-X-MEDIA:') &&
                RegExp(r'[:,]\s*URI=').hasMatch(line),
          );
    }
    if (session.filterAds && !manifest.isMaster && session._canFilterAds) {
      final filtered = filterDeclaredAds(manifest);
      manifest = filtered.manifest;
      session.timeline = filtered.timeline;
    }
    final playlists = manifest.playlistUris;
    for (final child in playlists) {
      session._variables[child] = manifest.variables;
    }
    session.prefetch.setManifest(manifest);
    final output = utf8.encode(
      manifest.rewrite(
        (uri) => session.register(uri, playlist: playlists.contains(uri)),
      ),
    );
    request.response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
    );
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.contentLength = output.length;
    if (request.method != 'HEAD') request.response.add(output);
  }

  Future<StoredResource> _fetch(
    GatewaySession session,
    Uri uri,
    String? range,
    String key,
  ) async {
    final payload = await _client.open(
      uri,
      policy: session.policy,
      range: range,
      cancellation: _transfers,
    );
    final response = payload.response;
    if (response.statusCode != 200 && response.statusCode != 206) {
      await payload.body.drain<void>();
      throw const HttpException('Media unavailable');
    }
    // A Range request is never relabelled 206 if the server ignores it.
    final headers = <String, String>{};
    for (final name in [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
    ]) {
      final value = response.headers.value(name);
      if (value != null) headers[name] = value;
    }
    return store.write(
      key,
      payload.body,
      statusCode: response.statusCode,
      headers: headers,
      expectedLength: response.contentLength < 0
          ? null
          : response.contentLength,
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _transfers.cancel();
    for (final session in _sessions.values.toList()) {
      session.close();
    }
    if (_ownsClient) _client.close();
    await _starting;
    await _server?.close(force: true);
    _server = null;
  }
}
