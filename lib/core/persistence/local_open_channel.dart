import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../network/loopback_request_policy.dart';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../platform/video_file_types.dart';

/// Per-owner capability endpoint. Only explicit local video paths are accepted.
final class LocalOpenChannel {
  LocalOpenChannel._(this._server, this._endpoint, this._secret);
  final HttpServer _server;
  final File _endpoint;
  final String _secret;
  final _requests = StreamController<String>();
  int _queued = 0;
  bool _closed = false;
  Stream<String> get requests => _requests.stream.map((path) {
    _queued--;
    return path;
  });

  static Future<LocalOpenChannel> start(Directory directory) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final endpoint = File(p.join(directory.path, '.open-endpoint.json'));
    final secret = base64Url.encode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final channel = LocalOpenChannel._(server, endpoint, secret);
    try {
      await endpoint.writeAsString(
        jsonEncode({'port': server.port, 'token': secret}),
        flush: true,
      );
      server.listen((request) => unawaited(channel._receive(request)));
      return channel;
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }

  Future<void> _receive(HttpRequest request) async {
    secureLoopbackResponse(request.response);
    try {
      if (_closed ||
          request.method != 'POST' ||
          request.uri.toString() != '/open' ||
          !isNativeLoopbackRequest(request, _server.port) ||
          request.headers.value('x-zero-open') != _secret) {
        request.response.statusCode = 403;
        return;
      }
      if (request.contentLength < 1 || request.contentLength > 65536) {
        request.response.statusCode = 413;
        return;
      }
      final path = utf8.decode(
        await request
            .fold<List<int>>([], (all, chunk) => all..addAll(chunk))
            .timeout(const Duration(seconds: 2)),
      );
      if (!p.isAbsolute(path) ||
          !isLocalVideo(path) ||
          path.contains('\x00') ||
          _queued >= 8) {
        request.response.statusCode = 400;
        return;
      }
      _queued++;
      _requests.add(path);
      request.response.statusCode = 202;
    } catch (_) {
      request.response.statusCode = 400;
    } finally {
      await request.response.close();
    }
  }

  static Future<bool> forward(Directory directory, String path) async {
    if (!p.isAbsolute(path) || !isLocalVideo(path)) return false;
    final endpoint = File(p.join(directory.path, '.open-endpoint.json'));
    for (var attempt = 0; attempt < 6; attempt++) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      try {
        if (await endpoint.length() > 4096) return false;
        final data = jsonDecode(await endpoint.readAsString()) as Map;
        final port = data['port'];
        if (port is! int ||
            port < 1 ||
            port > 65535 ||
            data['token'] is! String) {
          return false;
        }
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/open'),
        );
        final bytes = utf8.encode(path);
        request.headers.set('x-zero-open', data['token']);
        request.contentLength = bytes.length;
        request.add(bytes);
        final response = await request.close().timeout(
          const Duration(seconds: 1),
        );
        await response.drain<void>().timeout(const Duration(seconds: 1));
        return response.statusCode == 202;
      } catch (_) {
        if (attempt == 5) return false;
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
    if (await _endpoint.exists()) await _endpoint.delete();
    unawaited(_requests.close());
  }
}
