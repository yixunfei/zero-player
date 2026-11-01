import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'music_controller.dart';

/// Opt-in loopback compatibility for LX status/lyrics/SSE; no control or URL proxy.
final class MusicOpenApi extends ChangeNotifier {
  MusicOpenApi(this.player);
  final MusicController player;
  HttpServer? _server;
  Future<void>? _starting;
  final _clients = <HttpResponse, Set<String>>{};
  final _busy = <HttpResponse>{};
  Timer? _heartbeat;
  bool _closed = false;
  String? get address =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}';
  static const _defaultFields = {
    'status',
    'name',
    'singer',
    'albumName',
    'lyricLineText',
    'duration',
    'progress',
    'playbackRate',
  };
  Map<String, Object?> get snapshot {
    final track = player.selected;
    final visible = track != null && player.repository.allowed(track);
    return {
      'status': !visible
          ? 'stoped'
          : player.error != null
          ? 'error'
          : player.playing
          ? 'playing'
          : 'paused',
      'name': visible ? track.title : '',
      'singer': visible ? track.artist : '',
      'albumName': '',
      'duration': visible ? player.snapshot.duration.inMilliseconds / 1000 : 0,
      'progress': visible ? player.snapshot.position.inMilliseconds / 1000 : 0,
      'playbackRate': player.snapshot.rate,
      'volume': player.volume,
      'mute': player.volume == 0,
      'picUrl': visible ? track.cover : '',
      'lyric': '',
      'tlyric': '',
      'rlyric': '',
      'lxlyric': '',
      'lyricLineText': '',
      'lyricLineAllText': '',
      'collect': false,
    };
  }

  Future<void> start() =>
      _starting ??= _start().whenComplete(() => _starting = null);
  Future<void> _start() async {
    if (_closed || _server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      return;
    }
    _server = server;
    player.addListener(_changed);
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => _changed());
    server.listen((request) => unawaited(_handle(request)));
    notifyListeners();
  }

  Set<String> _fields(HttpRequest request) =>
      request.uri.queryParameters['filter'] == null
      ? _defaultFields
      : request.uri.queryParameters['filter']!
            .split(',')
            .where(snapshot.containsKey)
            .toSet();
  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    var streaming = false;
    try {
      if (request.method != 'GET') {
        response.statusCode = 405;
        return;
      }
      if (_server == null ||
          request.headers.value('host') != '127.0.0.1:${_server!.port}' ||
          request.headers.value('origin') != null ||
          request.headers.value('sec-fetch-site') != null ||
          request.uri.toString().length > 2048) {
        response.statusCode = 403;
        return;
      }
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Cache-Control', 'no-store');
      final state = snapshot;
      if (request.uri.path == '/status') {
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({for (final key in _fields(request)) key: state[key]}),
        );
      } else if (request.uri.path == '/lyric') {
        response.headers.contentType = ContentType(
          'text',
          'plain',
          charset: 'utf-8',
        );
      } else if (request.uri.path == '/lyric-all') {
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({'lyric': '', 'tlyric': '', 'rlyric': '', 'lxlyric': ''}),
        );
      } else if (request.uri.path == '/subscribe-player-status') {
        if (_clients.length >= 4) {
          response.statusCode = 429;
          return;
        }
        response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        response.bufferOutput = false;
        response.write(': connected\n\n');
        _clients[response] = _fields(request);
        streaming = true;
        unawaited(
          response.done.then(
            (_) => _forget(response),
            onError: (Object _) => _forget(response),
          ),
        );
        await _emit(response, state);
      } else {
        response.statusCode = 404;
      }
    } catch (_) {
      response.statusCode = 500;
    } finally {
      if (!streaming) {
        await response.close().catchError((Object _) {});
      }
    }
  }

  void _forget(HttpResponse response) {
    _clients.remove(response);
    _busy.remove(response);
  }

  void _changed() {
    final state = snapshot;
    for (final client in _clients.keys.toList()) {
      if (!_busy.contains(client)) unawaited(_emit(client, state));
    }
  }

  Future<void> _emit(HttpResponse client, Map<String, Object?> state) async {
    _busy.add(client);
    try {
      for (final field in _clients[client] ?? const <String>{}) {
        client.write('event: $field\ndata: ${jsonEncode(state[field])}\n\n');
      }
      await client.flush();
    } catch (_) {
      _forget(client);
      unawaited(client.close().catchError((Object _) {}));
    } finally {
      _busy.remove(client);
    }
  }

  Future<void> stop() async {
    await _starting;
    final server = _server;
    _server = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    player.removeListener(_changed);
    _clients.clear();
    _busy.clear();
    await server?.close(force: true);
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    _closed = true;
    await stop();
    super.dispose();
  }
}
