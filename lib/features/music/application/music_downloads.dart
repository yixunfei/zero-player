import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../core/network/media_http_client.dart';
import '../../../core/persistence/app_database.dart';
import '../../../media/cache/segment_fetcher.dart';
import '../../../media/gateway/offline_server.dart';
import '../../downloads/application/hls_download.dart';
import '../../downloads/application/mp4_download.dart';
import '../../sources/domain/video_source.dart';
import '../data/music_repository.dart';
import '../domain/music_track.dart';

final class MusicDownload {
  const MusicDownload(
    this.track,
    this.status,
    this.bytes, {
    this.entry,
    this.error,
  });
  final MusicTrack track;
  final String status;
  final int bytes;
  final String? entry, error;
}

final class MusicDownloads extends ChangeNotifier {
  MusicDownloads(
    this.db,
    this.root,
    this.repository,
    this.http,
    this.fetcher,
    this.offline, {
    required this.validate,
    this.resolve,
    this.maxBytes = 128 * 1024 * 1024,
    this.totalBytes = 1024 * 1024 * 1024,
  }) {
    repository.policy?.addListener(_policyChanged);
  }
  final AppDatabase db;
  final Directory root;
  final MusicRepository repository;
  final MediaHttpClient http;
  final SegmentFetcher fetcher;
  final OfflineServer offline;
  final Future<void> Function(File, CancellationToken) validate;
  final Future<MusicTrack> Function(MusicTrack, CancellationToken)? resolve;
  Future<void> get idle => _pending;
  final int maxBytes, totalBytes;
  List<MusicDownload> _items = [];
  List<MusicDownload> get items => _items;
  set items(List<MusicDownload> value) {
    _items = List.unmodifiable(value);
    _byRecording.clear();
    _complete = {
      for (final i in value)
        if (i.status == 'complete') i.track.key: i,
    };
    for (final item in _complete.values) {
      (_byRecording[_recording(item.track)] ??= []).add(item);
    }
  }

  final _byRecording = <String, List<MusicDownload>>{};
  Map<String, MusicDownload> _complete = {};
  String _recording(MusicTrack track) =>
      '${track.title.trim().toLowerCase()}|${track.artist.trim().toLowerCase()}';

  /// Cross-source matching is conservative: keep ambiguous recordings separate.
  MusicDownload? localFor(MusicTrack track) {
    final exact = completed(track);
    if (exact != null) return exact;
    if (track.artist.trim().isEmpty || !repository.allowed(track)) return null;
    final candidates =
        (_byRecording[_recording(track)] ?? const <MusicDownload>[])
            .where(
              (item) =>
                  repository.allowed(item.track) &&
                  (item.track.duration == Duration.zero ||
                      track.duration == Duration.zero ||
                      (item.track.duration - track.duration).inMilliseconds
                              .abs() <=
                          2000),
            )
            .toList();
    return candidates.length == 1 ? candidates.single : null;
  }

  MusicDownload? completed(MusicTrack track) {
    final exact = _complete[track.key];
    return exact != null && repository.allowed(exact.track) ? exact : null;
  }

  List<MusicTrack> searchLocal(String query) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    if (words.every((word) => word.isEmpty)) return [];
    return [
      for (final item in _complete.values)
        if (repository.allowed(item.track) &&
            words.every(
              ('${item.track.title} ${item.track.artist}'.toLowerCase())
                  .contains,
            ))
          item.track,
    ];
  }

  final _tokens = <String, CancellationToken>{};
  final _removing = <String>{};
  CancellationToken? _activeToken;
  Completer<void>? _activeDone;
  Future<void> _pending = Future.value();
  Future<void>? _loaded;
  bool _closed = false;
  String id(MusicTrack track) => stableId(track.key);
  Directory directory(MusicTrack track) =>
      Directory(p.join(root.path, id(track)));
  Future<void> load() => _loaded ??= _read(recover: true);
  Future<void> _read({bool recover = false}) async {
    final rows = await db.rows(
      "SELECT key,value FROM app_meta WHERE key GLOB 'music_download:*'",
    );
    final result = <MusicDownload>[];
    for (final row in rows) {
      try {
        final data = jsonDecode(row['value'] as String) as Map;
        if (recover && {'queued', 'downloading'}.contains(data['status'])) {
          data['status'] = 'paused';
          await db.write('UPDATE app_meta SET value=? WHERE key=?', [
            jsonEncode(data),
            row['key'],
          ]);
        }
        final item = MusicDownload(
          MusicTrack.fromJson(data['track'] as Map),
          recover && {'queued', 'downloading'}.contains(data['status'])
              ? 'paused'
              : data['status'] as String,
          data['bytes'] as int,
          entry: data['entry'] as String?,
          error: data['error'] as String?,
        );
        result.add(item);
      } catch (_) {
        /* Preserve corrupt metadata, never use it as a path. */
      }
    }
    items = result;
    if (!_closed) notifyListeners();
  }

  Future<void> _save(
    MusicTrack track,
    String status, {
    int bytes = 0,
    String? entry,
    String? error,
  }) async {
    await db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      'music_download:${id(track)}',
      jsonEncode({
        'track': track.toJson(),
        'status': status,
        'bytes': bytes,
        'entry': entry,
        'error': error,
      }),
    ]);
    final updated = MusicDownload(
      track,
      status,
      bytes,
      entry: entry,
      error: error,
    );
    items = [
      for (final item in items)
        if (item.track.key == track.key) updated else item,
      if (!items.any((item) => item.track.key == track.key)) updated,
    ];
    if (!_closed) notifyListeners();
  }

  void _policyChanged() {
    for (final token in _tokens.values) {
      token.cancel();
    }
  }

  Future<void> download(MusicTrack track) async {
    await load();
    if (_closed ||
        _removing.contains(id(track)) ||
        _tokens[id(track)]?.isCancelled == false) {
      return;
    }
    if (!repository.allowed(track)) throw const FormatException('歌曲已被过滤');
    if (!track.canDownload) {
      throw const FormatException('该音源未开放此歌曲下载');
    }
    if (items.any(
      (item) => item.track.key == track.key && item.status == 'complete',
    )) {
      return;
    }
    if (items.length >= 500 &&
        !items.any((item) => item.track.key == track.key)) {
      throw const FormatException('离线任务最多 500 项');
    }
    final token = _tokens[id(track)] = CancellationToken();
    try {
      await _save(track, 'queued');
    } catch (_) {
      if (identical(_tokens[id(track)], token)) _tokens.remove(id(track));
      rethrow;
    }
    final job = _pending.then((_) => _execute(track, token));
    _pending = job.catchError((Object _) {});
    unawaited(
      job
          .whenComplete(() {
            if (identical(_tokens[id(track)], token)) _tokens.remove(id(track));
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> _execute(MusicTrack track, CancellationToken token) async {
    if (_closed || !identical(_tokens[id(track)], token)) return;
    if (token.isCancelled) {
      final item = items.where((i) => i.track.key == track.key).firstOrNull;
      if (item?.status == 'queued') {
        await _save(track, 'paused', bytes: item!.bytes);
      }
      return;
    }
    final done = _activeDone = Completer<void>();
    _activeToken = token;
    try {
      await _run(track, token);
    } finally {
      _activeToken = null;
      _activeDone = null;
      done.complete();
    }
  }

  Future<void> _run(MusicTrack track, CancellationToken token) async {
    var bytes = 0;
    try {
      token.check();
      final media =
          await (resolve?.call(track, token) ??
              repository.resolve(track, token, refresh: true));
      if (!repository.allowed(media)) throw const FormatException('歌曲已被过滤');
      if (!media.canDownload) throw const FormatException('该音源未开放此歌曲下载');
      final dir = directory(track);
      await dir.create(recursive: true);
      final retained = await _retainedBytes();
      final reusable = await _reusableBytes(track, media.url);
      final budget = (totalBytes - retained + reusable).clamp(0, maxBytes);
      if (budget <= 0) throw const FileSystemException('音乐离线空间已满，请删除部分下载');
      Future<void> progress(int completed, int total, int size) async {
        bytes = size;
        token.check();
        await _save(track, 'downloading', bytes: bytes);
      }

      await _save(track, 'downloading');
      final policy = HeaderPolicy({media.url: repository.headers(media)});
      String entry;
      if (media.url.path.toLowerCase().endsWith('.m3u8')) {
        entry = await HlsDownload(
          id: 'music:${id(track)}',
          directory: dir,
          fetcher: fetcher,
          http: http,
          policy: policy,
          cancellation: token,
          maxBytes: budget,
          onProgress: progress,
        ).run(media.url);
      } else {
        entry = _audioName(media.url);
        await downloadMp4(
          uri: media.url,
          directory: dir,
          http: http,
          policy: policy,
          cancellation: token,
          maxBytes: budget,
          progress: progress,
          validate: validate,
          fileName: entry,
        );
      }
      token.check();
      if (!repository.allowed(track)) throw const FormatException('歌曲已被过滤');
      await _save(track, 'complete', bytes: bytes, entry: entry);
    } catch (_) {
      await _save(
        track,
        token.isCancelled ? 'paused' : 'failed',
        bytes: bytes,
        error: token.isCancelled ? null : '下载未完成，可重试；请检查音源及剩余容量。',
      );
    }
  }

  Future<int> _reusableBytes(MusicTrack track, Uri uri) async {
    if (uri.path.toLowerCase().endsWith('.m3u8')) {
      return (await fetcher.store.pinnedResources(
        'music:${id(track)}',
      )).values.fold<int>(0, (sum, value) => sum + value);
    }
    final part = File(p.join(directory(track).path, '${_audioName(uri)}.part'));
    return await part.exists() ? await part.length() : 0;
  }

  Future<int> _retainedBytes() async {
    var bytes = 0;
    for (final item in items) {
      bytes += (await fetcher.store.pinnedResources(
        'music:${id(item.track)}',
      )).values.fold(0, (sum, value) => sum + value);
    }
    if (await root.exists()) {
      await for (final file in root.list(recursive: true, followLinks: false)) {
        if (file is File) bytes += await file.length();
      }
    }
    return bytes;
  }

  Future<void> pause(MusicTrack track) async {
    await load();
    final token = _tokens[id(track)];
    if (token == null) return;
    token.cancel();
    if (identical(_activeToken, token)) {
      await _activeDone?.future;
    } else {
      final item = items.where((i) => i.track.key == track.key).firstOrNull;
      if (item?.status == 'queued') {
        await _save(track, 'paused', bytes: item!.bytes);
      }
    }
  }

  Future<OfflineSession?> open(MusicTrack track) async {
    await load();
    final item = items
        .where((i) => i.track.key == track.key && i.status == 'complete')
        .firstOrNull;
    if (item == null) return null;
    if (!repository.allowed(track)) throw const FormatException('歌曲已被过滤');
    try {
      return await offline.open(
        'music:${id(track)}',
        directory(track),
        item.entry!,
      );
    } catch (_) {
      await _save(
        track,
        'failed',
        bytes: item.bytes,
        error: '离线文件缺失或损坏，请重试下载。',
      );
      rethrow;
    }
  }

  Future<void> remove(MusicTrack track) async {
    if (!_removing.add(id(track))) return;
    try {
      await _remove(track);
    } finally {
      _removing.remove(id(track));
    }
  }

  Future<void> _remove(MusicTrack track) async {
    await pause(track);
    if (offline.isPlaying('music:${id(track)}')) {
      throw const FormatException('请先停止这首歌曲再删除下载');
    }
    final dir = directory(track);
    final base = p.normalize(p.absolute(root.path));
    final target = p.normalize(p.absolute(dir.path));
    if (!p.isWithin(base, target)) throw const FormatException('无效的下载目录');
    _tokens.remove(id(track));
    await fetcher.store.unpin('music:${id(track)}');
    if (await dir.exists()) await dir.delete(recursive: true);
    await db.write('DELETE FROM app_meta WHERE key=?', [
      'music_download:${id(track)}',
    ]);
    await _read();
  }

  Future<void> close() async {
    _closed = true;
    _policyChanged();
    await _pending;
    repository.policy?.removeListener(_policyChanged);
    super.dispose();
  }
}

String _audioName(Uri uri) {
  final extension = p.extension(uri.path).toLowerCase();
  return 'audio${{'.mp3', '.m4a', '.aac', '.flac', '.ogg', '.wav'}.contains(extension) ? extension : '.mp3'}';
}
