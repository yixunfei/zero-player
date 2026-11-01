import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/data/music_library.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import 'package:zero_player/features/settings/data/backup_service.dart';

MusicTrack track(String id, {String provider = 'myfreemp3'}) => MusicTrack(
  id: id,
  title: id,
  artist: 'artist',
  url: Uri.parse('https://example.com/$id.mp3'),
  fetchedAt: DateTime.now(),
  provider: provider,
);

void main() {
  test(
    'playlists, namespaced identities, ordering, history and mode survive restart',
    () async {
      final root = await Directory.systemTemp.createTemp('music-library-');
      final file = File('${root.path}/test.sqlite');
      var db = AppDatabase(file);
      var library = MusicLibrary(db);
      final id = await library.create('我的歌单');
      await library.add(id, track('a'));
      await library.add(id, track('a'));
      await library.add(id, track('a', provider: 'netease'));
      await library.add(id, track('b'));
      await library.move(id, track('b').key, -1);
      await library.rename(id, '旅行');
      await library.record(
        track('a'),
        const PlaybackSnapshot(
          position: Duration(seconds: 12),
          duration: Duration(seconds: 90),
        ),
      );
      await library.setMode(MusicPlayMode.repeatAll);
      await library.close();
      await db.close();
      db = AppDatabase(file);
      library = MusicLibrary(db);
      await library.load();
      expect(library.playlists.single.name, '旅行');
      expect(library.playlists.single.tracks.map((t) => t.key), [
        'myfreemp3:a',
        'myfreemp3:b',
        'netease:a',
      ]);
      expect(library.history.single.position, const Duration(seconds: 12));
      expect(library.mode, MusicPlayMode.repeatAll);
      await library.remove(id, track('a').key);
      expect(library.playlists.single.tracks, hasLength(2));
      await library.clearHistory();
      expect(library.history, isEmpty);
      await library.delete(id);
      expect(library.playlists, isEmpty);
      await library.close();
      await db.close();
      await root.delete(recursive: true);
    },
  );
  test(
    'music metadata participates in backups and invalid track URLs are rejected',
    () async {
      final db = AppDatabase.memory();
      final library = MusicLibrary(db);
      addTearDown(() async {
        await library.close();
        await db.close();
      });
      final id = await library.create('备份歌单');
      await library.add(id, track('a'));
      final backup = BackupService(db);
      final text = await backup.export();
      await library.delete(id);
      await backup.restore(await backup.preview(text));
      await library.reload();
      expect(library.playlists.single.tracks.single.id, 'a');
      expect(
        () => MusicTrack.fromJson({
          ...track('a').toJson(),
          'url': 'file:///C:/secret.mp3',
        }),
        throwsFormatException,
      );
      expect(
        () => MusicPlaylist.fromJson({'id': id, 'name': '', 'tracks': []}),
        throwsFormatException,
      );
    },
  );
}
