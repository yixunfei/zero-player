import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/network/loopback_request_policy.dart';
import 'dart:math';

import 'filter_session.dart';

/// A capability server with no route to raw input or not-yet-approved files.
final class ApprovedMediaServer {
  final _sessions = <String, FilterSession>{};
  HttpServer? _server;
  Future<void>? _starting;
  Future<void>? _closing;

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Uri register(FilterSession session) {
    if (_server == null || _closing != null) {
      throw StateError('Server unavailable');
    }
    final random = Random.secure();
    final id = base64Url.encode(List.generate(24, (_) => random.nextInt(256)));
    _sessions[id] = session;
    return Uri.parse('http://127.0.0.1:${_server!.port}/$id/index.m3u8');
  }

  void unregister(FilterSession session) =>
      _sessions.removeWhere((_, value) => identical(value, session));

  bool isRegisteredPlaylist(Uri uri) =>
      _validUri(uri) &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments[1] == 'index.m3u8' &&
      _sessions[uri.pathSegments[0]]?.closed == false;

  bool _validUri(Uri uri) =>
      _server != null &&
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      uri.port == _server!.port &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;

  Future<void> _handle(HttpRequest request) async {
    secureLoopbackResponse(request.response);
    try {
      if (!{'GET', 'HEAD'}.contains(request.method)) {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      if (!isNativeLoopbackRequest(request, _server!.port) ||
          request.uri.pathSegments.length != 2) {
        request.response.statusCode = HttpStatus.forbidden;
        return;
      }
      final parts = request.uri.pathSegments;
      final session = _sessions[parts[0]];
      if (session == null || session.closed) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      if (parts[1] == 'index.m3u8') {
        _manifest(request, session);
      } else {
        await _media(request, session, parts[1]);
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } catch (_) {}
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  void _manifest(HttpRequest request, FilterSession session) {
    final slices = session.available;
    if (slices.isEmpty) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    final text = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n')
      ..writeln('#EXT-X-TARGETDURATION:${session.sliceDuration.inSeconds + 1}')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:${slices.first.sequence}');
    for (final slice in slices) {
      text
        ..writeln(
          '#EXTINF:${(slice.duration.inMicroseconds / 1e6).toStringAsFixed(6)},',
        )
        ..writeln('${slice.sequence}.ts');
    }
    if (session.finished) text.writeln('#EXT-X-ENDLIST');
    final bytes = utf8.encode(text.toString());
    request.response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
    );
    request.response.contentLength = bytes.length;
    if (request.method == 'GET') request.response.add(bytes);
  }

  Future<void> _media(
    HttpRequest request,
    FilterSession session,
    String name,
  ) async {
    final match = RegExp(r'^(\d+)\.ts$').firstMatch(name);
    final index = match == null ? null : int.tryParse(match[1]!);
    final slice = session.available
        .where((s) => s.sequence == index)
        .firstOrNull;
    if (slice == null) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final file = File(slice.path);
    request.response.headers.contentType = ContentType('video', 'mp2t');
    request.response.contentLength = await file.length();
    if (request.method == 'GET') {
      await request.response.addStream(file.openRead());
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await _starting;
    await _server?.close(force: true);
    for (final session in _sessions.values.toList()) {
      await session.close();
    }
    _sessions.clear();
  }
}
