import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/persistence/app_database.dart';
import '../../sources/domain/video_source.dart';
import '../../playback/domain/player_engine.dart';
import '../domain/music_track.dart';

enum MusicPlayMode { sequential, repeatAll, repeatOne, shuffle }

const musicModeLabels = ['顺序播放', '列表循环', '单曲循环', '随机播放'];

final class MusicPlaylist {
  const MusicPlaylist(this.id, this.name, this.tracks);
  final String id, name;
  final List<MusicTrack> tracks;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };
  factory MusicPlaylist.fromJson(Map data) {
    final name = data['name'] as String;
    final tracks = data['tracks'] as List;
    if (name.trim().isEmpty ||
        name.length > 80 ||
        tracks.length > 500 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(data['id'] as String)) {
      throw const FormatException('歌单名称或容量无效');
    }
    return MusicPlaylist(
      data['id'] as String,
      name,
      List.unmodifiable(tracks.cast<Map>().map(MusicTrack.fromJson)),
    );
  }
}

final class MusicHistory {
  const MusicHistory(this.track, this.position, this.playedAt);
  final MusicTrack track;
  final Duration position;
  final DateTime playedAt;
}

final class MusicLibrary extends ChangeNotifier {
  MusicLibrary(this.db);
  final AppDatabase db;
  List<MusicPlaylist> playlists = [];
  List<MusicHistory> history = [];
  MusicPlayMode mode = MusicPlayMode.sequential;
  Future<void>? _loaded;
  Future<void> _pending = Future.value();
  bool _closed = false;
  String? notice;
  Future<void> load() => _loaded ??= _read();
  Future<void> get pendingWrites => _pending;
  Future<void> reload() async {
    await _pending;
    await _read();
  }

  Future<void> _read() async {
    final rows = await db.rows(
      "SELECT * FROM app_meta WHERE key GLOB 'music_playlist:*' OR key GLOB 'music_history:*' OR key='music_mode'",
    );
    final lists = <MusicPlaylist>[];
    final records = <MusicHistory>[];
    for (final row in rows) {
      try {
        final key = row['key'] as String;
        final value = jsonDecode(row['value'] as String);
        if (key == 'music_mode') {
          mode = MusicPlayMode.values.byName(value as String);
        } else if (key.startsWith('music_playlist:')) {
          lists.add(MusicPlaylist.fromJson(value as Map));
        } else {
          final map = value as Map;
          records.add(
            MusicHistory(
              MusicTrack.fromJson(map['track'] as Map),
              Duration(milliseconds: map['position'] as int),
              DateTime.fromMillisecondsSinceEpoch(map['playedAt'] as int),
            ),
          );
        }
      } catch (_) {
        notice = '部分音乐记录损坏，已保留原数据并跳过。';
      }
    }
    playlists = lists;
    history = records..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    if (!_closed) notifyListeners();
  }

  Future<void> _write(Future<void> Function() action) {
    if (_closed) return Future.error(StateError('音乐库已关闭'));
    final future = _pending.then((_) async {
      await load();
      await action();
      await _read();
    });
    _pending = future.catchError((Object _) {});
    return future;
  }

  Future<String> create(String name) async {
    final id = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _write(() async {
      if (playlists.length >= 100) throw const FormatException('最多创建 100 个歌单');
      await _save(
        MusicPlaylist.fromJson({'id': id, 'name': name.trim(), 'tracks': []}),
      );
    });
    return id;
  }

  Future<void> _save(MusicPlaylist list) => db.write(
    'INSERT OR REPLACE INTO app_meta VALUES(?,?)',
    ['music_playlist:${list.id}', jsonEncode(list.toJson())],
  );
  Future<void> rename(String id, String name) => _write(() async {
    final list = playlists.firstWhere((p) => p.id == id);
    await _save(
      MusicPlaylist.fromJson({...list.toJson(), 'name': name.trim()}),
    );
  });
  Future<void> delete(String id) => _write(
    () => db.write('DELETE FROM app_meta WHERE key=?', ['music_playlist:$id']),
  );
  Future<void> add(String id, MusicTrack track) => _write(() async {
    final list = playlists.firstWhere((p) => p.id == id);
    if (list.tracks.any((t) => t.key == track.key)) return;
    if (list.tracks.length >= 500) throw const FormatException('每个歌单最多 500 首');
    await _save(MusicPlaylist(id, list.name, [...list.tracks, track]));
  });
  Future<void> remove(String id, String key) => _write(() async {
    final list = playlists.firstWhere((p) => p.id == id);
    await _save(
      MusicPlaylist(
        id,
        list.name,
        list.tracks.where((t) => t.key != key).toList(),
      ),
    );
  });
  Future<void> move(String id, String key, int delta) => _write(() async {
    final list = playlists.firstWhere((p) => p.id == id);
    final tracks = list.tracks.toList();
    final from = tracks.indexWhere((t) => t.key == key);
    if (from < 0) return;
    final to = (from + delta).clamp(0, tracks.length - 1);
    final item = tracks.removeAt(from);
    tracks.insert(to, item);
    await _save(MusicPlaylist(id, list.name, tracks));
  });
  Future<void> setMode(MusicPlayMode value) => _write(
    () => db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      'music_mode',
      jsonEncode(value.name),
    ]),
  );
  Future<void> record(
    MusicTrack track,
    PlaybackSnapshot state,
  ) => _write(() async {
    if (state.duration <= Duration.zero) return;
    await db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      'music_history:${stableId(track.key)}',
      jsonEncode({
        'track': track.toJson(),
        'position': state.position.inMilliseconds.clamp(
          0,
          state.duration.inMilliseconds,
        ),
        'playedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    ]);
    final rows = await db.rows(
      "SELECT key FROM app_meta WHERE key GLOB 'music_history:*' ORDER BY json_extract(value,'\$.playedAt') DESC LIMIT -1 OFFSET 200",
    );
    for (final row in rows) {
      await db.write('DELETE FROM app_meta WHERE key=?', [row['key']]);
    }
  });
  Future<void> clearHistory() => _write(
    () => db.write("DELETE FROM app_meta WHERE key GLOB 'music_history:*'"),
  );
  Future<void> close() async {
    await _pending;
    _closed = true;
    super.dispose();
  }
}

bool validateMusicMetadata(String key, String text) {
  if (!(key.startsWith('music_playlist:') ||
      key.startsWith('music_history:') ||
      key == 'music_mode')) {
    return false;
  }
  final value = jsonDecode(text);
  if (key == 'music_mode') {
    MusicPlayMode.values.byName(value as String);
  } else if (key.startsWith('music_playlist:')) {
    final playlist = MusicPlaylist.fromJson(value as Map);
    if (key != 'music_playlist:${playlist.id}') {
      throw const FormatException('歌单标识无效');
    }
  } else {
    final data = value as Map;
    final track = MusicTrack.fromJson(data['track'] as Map);
    if (key != 'music_history:${stableId(track.key)}' ||
        data['position'] is! int ||
        (data['position'] as int) < 0 ||
        data['playedAt'] is! int) {
      throw const FormatException('播放历史无效');
    }
  }
  return true;
}

void validateMusicCollection(List<Map<String, Object?>> rows) {
  final playlists = rows
      .where((row) => (row['key'] as String).startsWith('music_playlist:'))
      .length;
  final history = rows
      .where((row) => (row['key'] as String).startsWith('music_history:'))
      .length;
  if (playlists > 100 || history > 200) {
    throw const FormatException('音乐备份超过歌单或历史容量限制');
  }
}
