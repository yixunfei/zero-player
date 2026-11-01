import '../../core/platform/video_files.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/network/file_response.dart';
import '../cache/segment_store.dart';

final class OfflineSession {
  OfflineSession(this.uri, this.close);
  final Uri uri;
  final void Function() close;
}

final class OfflineServer {
  OfflineServer(this.store);
  final SegmentStore store;
  HttpServer? _server;
  Future<void>? _starting;
  Future<void>? _closing;
  int _generation = 0;
  final _sessions = <String, Map<String, File>>{};
  final _tasks = <String, String>{};
  final _localFiles = <String, String>{};
  Iterable<String> get activeLocalFiles => _localFiles.values.toList();
  Future<void> _localQueue = Future.value();

  Future<T> _localOperation<T>(Future<T> Function() action) {
    final operation = _localQueue.then((_) => action());
    _localQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> clearLocalCopies() =>
      _localOperation(() => VideoFiles.clearLocalCopies(activeLocalFiles));
  bool isPlaying(String id) => _tasks.containsValue(id);

  bool isRegisteredResource(Uri uri) {
    if (_server == null ||
        uri.scheme != 'http' ||
        uri.authority != '127.0.0.1:${_server!.port}' ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final parts = uri.pathSegments;
    return parts.length == 2 &&
        _sessions[parts[0]]?.containsKey(parts[1]) == true;
  }

  bool isRegisteredPlaylist(Uri uri) {
    if (_server == null ||
        uri.scheme != 'http' ||
        uri.authority != '127.0.0.1:${_server!.port}' ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final parts = uri.pathSegments;
    return parts.length == 2 &&
        parts[1].endsWith('.m3u8') &&
        _sessions[parts[0]]?.containsKey(parts[1]) == true;
  }

  Future<OfflineSession> open(
    String taskId,
    Directory directory,
    String entry,
  ) async {
    if (p.basename(entry) != entry) throw const FormatException('无效的离线入口');
    await _closing;
    final generation = _generation;
    await _ensureStarted();
    final files = <String, File>{};
    final descriptor = File(p.join(directory.path, 'resources.json'));
    if (RegExp(r'\.(mp4|mp3|m4a|aac|flac|ogg|wav)$').hasMatch(entry)) {
      files[entry] = File(p.join(directory.path, entry));
      final integrity =
          jsonDecode(
                await File(
                  p.join(directory.path, 'integrity.json'),
                ).readAsString(),
              )
              as Map;
      if (await files[entry]!.length() != integrity['bytes'] ||
          '${await sha256.bind(files[entry]!.openRead()).first}' !=
              integrity['digest']) {
        throw const FileSystemException('离线文件损坏，请重新下载');
      }
    } else {
      final mappings = jsonDecode(await descriptor.readAsString()) as Map;
      for (final record in mappings.entries) {
        final name = record.key as String;
        if (p.basename(name) != name) throw const FormatException('无效的离线资源名');
        final value = record.value as Map;
        if (value['key'] != null) {
          final key = value['key'] as String;
          await store.verify(key);
          files[name] = store.find(key)!.file;
        } else {
          if (value['local'] != name) throw const FormatException('无效的离线映射');
          files[name] = File(p.join(directory.path, name));
          if (value['digest'] !=
              '${await sha256.bind(files[name]!.openRead()).first}') {
            throw const FileSystemException('离线清单已损坏，请重新下载');
          }
        }
        if (!await files[name]!.exists()) {
          throw const FileSystemException('离线文件缺失');
        }
      }
    }
    if (!files.containsKey(entry)) throw const FormatException('离线入口不存在');
    if (generation != _generation || _server == null) {
      throw StateError('离线服务器已关闭，请重新打开');
    }
    final random = Random.secure();
    final token = base64Url.encode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    _sessions[token] = files;
    _tasks[token] = taskId;
    return OfflineSession(
      Uri.parse('http://127.0.0.1:${_server!.port}/$token/$entry'),
      () {
        _sessions.remove(token);
        _tasks.remove(token);
      },
    );
  }

  /// Expose only the selected file; adjacent files and playlists stay inaccessible.
  Future<OfflineSession> openLocal(File file) =>
      _localOperation(() => _openLocal(file));

  Future<OfflineSession> _openLocal(File file) async {
    if (!isLocalVideo(file.path)) {
      throw const FormatException('不支持此视频格式');
    }
    if (!await file.exists()) {
      throw const FileSystemException('视频文件不存在');
    }
    await _closing;
    final generation = _generation;
    await _ensureStarted();
    if (generation != _generation || _server == null) {
      throw StateError('播放器已关闭');
    }
    final token = base64Url.encode(
      List.generate(24, (_) => Random.secure().nextInt(256)),
    );
    final name = 'video${p.extension(file.path).toLowerCase()}';
    _sessions[token] = {name: file};
    _localFiles[token] = file.path;
    _tasks[token] = 'local:$token';
    return OfflineSession(
      Uri.parse('http://127.0.0.1:${_server!.port}/$token/$name'),
      () {
        _sessions.remove(token);
        _tasks.remove(token);
        _localFiles.remove(token);
      },
    );
  }

  Future<void> _ensureStarted() {
    if (_server != null) return Future.value();
    return _starting ??= _start(
      _generation,
    ).whenComplete(() => _starting = null);
  }

  Future<void> _start(int generation) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (generation != _generation) {
      await server.close(force: true);
      return;
    }
    _server = server;
    server.listen((request) => unawaited(_serve(request)));
  }

  Future<void> _serve(HttpRequest request) async {
    try {
      final parts = request.uri.pathSegments;
      final File? file = parts.length == 2
          ? (_sessions[parts[0]]?[parts[1]])
          : null;
      if (!{'GET', 'HEAD'}.contains(request.method)) {
        request.response.statusCode = 405;
        return;
      }
      if (file == null ||
          request.headers.value('origin') != null ||
          request.headers.value('sec-fetch-site') != null ||
          request.headers.value('host') != '127.0.0.1:${_server!.port}') {
        request.response.statusCode = 404;
        return;
      }
      final type = parts.last.endsWith('.m3u8')
          ? 'application/vnd.apple.mpegurl'
          : parts.last.endsWith('.mp4') || parts.last.endsWith('.m4s')
          ? 'video/mp4'
          : 'application/octet-stream';
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      request.response.headers.set(
        'Content-Security-Policy',
        "default-src 'none'; sandbox",
      );
      await serveLocalFile(request, file, contentType: type);
    } catch (_) {
      try {
        request.response.statusCode = 500;
      } catch (_) {}
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() =>
      _closing ??= _close().whenComplete(() => _closing = null);

  Future<void> _close() async {
    _generation++;
    _sessions.clear();
    _tasks.clear();
    _localFiles.clear();
    final server = _server;
    _server = null;
    await _starting;
    await server?.close(force: true);
  }
}
