import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/network/loopback_request_policy.dart';
import '../../core/network/cancellation_token.dart';
import '../../core/network/header_policy.dart';
import '../../core/network/media_http_client.dart';
import '../../core/network/network_target_policy.dart';
import '../cache/resource_identity.dart';
import '../cache/segment_store.dart';
import '../cache/segment_fetcher.dart';
import '../cache/segment_prefetcher.dart';
import '../hls/hls_manifest.dart';
import '../hls/hls_quality.dart';
import '../hls/ad_filter.dart';
import '../hls/timeline.dart';
import 'timestamp_segments.dart';
import '../network/media_response_policy.dart';

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
  bool normalizeTimestamps = false;
  final _timestamps = TimestampSegments();
  String get timestampStatus => !normalizeTimestamps
      ? '时间轴修正未启用'
      : !_canFilterAds
      ? '多路音视频清单，未改写时钟'
      : '${_timestamps.status}；本次生成修正 ${_timestamps.corrected} 段，未改动 ${_timestamps.unchanged} 段';
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

  Future<Uri> openMedia(Uri uri) async {
    NetworkTargetPolicy.validateUri(uri);
    var hls = uri.path.toLowerCase().endsWith('.m3u8');
    if (!hls &&
        !RegExp(
          r'\.(mp3|aac|mp4|flv|mkv|webm|ts|ogg|wav|flac)$',
          caseSensitive: false,
        ).hasMatch(uri.path)) {
      final payload = await _gateway._client.open(
        uri,
        policy: policy,
        cancellation: cancellation,
      );
      final first = await payload.body.take(1).toList();
      hls =
          first.isNotEmpty &&
          utf8
              .decode(first.first.take(512).toList(), allowMalformed: true)
              .trimLeft()
              .startsWith('#EXTM3U');
    }
    cancellation.check();
    return register(uri, playlist: hls, streaming: !hls);
  }

  Uri register(Uri uri, {bool playlist = false, bool streaming = false}) {
    if (_closed) throw StateError('Session is closed');
    NetworkTargetPolicy.validateUri(uri);
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
    _playlists.clear();
    _streaming.clear();
    _variables.clear();
    _timestamps.clear();
    _gateway._sessions.remove(token);
  }
}

/// Capability URLs map to registered resources; there is no arbitrary URL
/// query parameter and the socket is bound exclusively to IPv4 loopback.
final class MediaGateway {
  MediaGateway(
    this.store, {
    MediaHttpClient? client,
    bool allowPrivateNetworks = false,
  }) : _client =
           client ??
           MediaHttpClient(allowPrivateNetworks: allowPrivateNetworks),
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

  bool isRegisteredResource(Uri uri) {
    if (_server == null ||
        uri.scheme != 'http' ||
        uri.origin != baseUri.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final parts = uri.pathSegments;
    return parts.length == 2 &&
        _sessions[parts[0]]?._resources.containsKey(parts[1]) == true;
  }

  bool isRegisteredPlaylist(Uri uri) {
    if (_server == null ||
        uri.scheme != 'http' ||
        uri.origin != baseUri.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final parts = uri.pathSegments;
    if (parts.length != 2) return false;
    final session = _sessions[parts[0]];
    final resource = session?._resources[parts[1]];
    return resource != null && session!._playlists.contains(resource);
  }

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
    secureLoopbackResponse(request.response);
    ResourceLease? lease;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      // Native capability URLs must not become a browser fetch endpoint.
      if (!isNativeLoopbackRequest(request, _server!.port)) {
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
      // Recheck revoked permissions even when serving an existing cache entry.
      _client.targetPolicy.validateAccess(
        uri,
        originalOrigin: session.policy.containsOrigin(uri),
      );
      requests++;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && !RegExp(r'^bytes=(\d+-\d*|-\d+)$').hasMatch(range)) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        return;
      }
      if (session._playlists.contains(uri)) {
        await _manifest(request, session, uri);
      } else if (session.normalizeTimestamps &&
          await session._timestamps.serve(
            request,
            uri,
            store,
            session.policy,
            (key) => _fetch(session, uri, null, key),
          )) {
        return;
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
        validateMediaType(resource.headers[HttpHeaders.contentTypeHeader]);
        session.prefetch.observe(uri, resource.length, range: range);
        request.response.statusCode = resource.statusCode;
        resource.headers.forEach(request.response.headers.set);
        request.response.contentLength = resource.length;
        if (request.method != 'HEAD') {
          await request.response.addStream(
            guardMediaBody(
              resource.file.openRead(),
              inspectPrefix: startsMediaEntity(
                resource.headers[HttpHeaders.contentRangeHeader],
                requestedRange: range,
              ),
            ),
          );
        }
      }
    } catch (_) {
      failures++;
      // Never expose signed upstream URLs, headers, tokens or raw exceptions.
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.contentLength = -1;
        request.response.headers.contentType = ContentType.text;
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
    final body = StreamIterator(
      guardMediaBody(
        payload.body,
        inspectPrefix: startsMediaEntity(
          payload.response.headers.value(HttpHeaders.contentRangeHeader),
          requestedRange: range,
        ),
      ),
    );
    var hasFirst = false;
    Stream<List<int>> chunks() async* {
      if (hasFirst) yield body.current;
      while (await body.moveNext()) {
        yield body.current;
      }
    }

    try {
      validateMediaType(
        payload.response.headers.value(HttpHeaders.contentTypeHeader),
      );
      // addStream commits headers even if its first event is an error. Inspect
      // the first guarded chunk before committing any upstream response state.
      if (request.method != 'HEAD') hasFirst = await body.moveNext();
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
      await payload.body.take(0).drain<void>();
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
    if (session.normalizeTimestamps && session._canFilterAds) {
      session._timestamps.register(manifest);
    }
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
      await payload.body.take(0).drain<void>();
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
    try {
      validateMediaType(response.headers.value(HttpHeaders.contentTypeHeader));
    } catch (_) {
      await payload.body.take(0).drain<void>();
      rethrow;
    }
    return store.write(
      key,
      guardMediaBody(
        payload.body,
        inspectPrefix: startsMediaEntity(
          response.headers.value(HttpHeaders.contentRangeHeader),
          requestedRange: range,
        ),
      ),
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
