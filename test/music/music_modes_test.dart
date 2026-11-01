import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/application/music_controller.dart';
import 'package:zero_player/features/music/data/music_library.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  for (final mode in MusicPlayMode.values) {
    test('completion respects ${mode.name}', () async {
      final http = MediaHttpClient();
      final engines = <FakePlayerEngine>[];
      final player = MusicController(
        MusicRepository(MyFreeMp3Client(DocumentClient(http))),
        () {
          final engine = FakePlayerEngine();
          engines.add(engine);
          return engine;
        },
      );
      addTearDown(() async {
        await player.close();
        http.close();
      });
      final tracks = [
        for (final name in ['one', 'two', 'three'])
          MusicTrack(
            id: name,
            title: name,
            artist: '',
            url: Uri.parse('https://example.com/$name.mp3'),
            fetchedAt: DateTime.now(),
          ),
      ];
      await player.setMode(mode);
      await player.select(tracks, 2);
      engines.last.emit(const PlaybackSnapshot(completed: true));
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(player.selected?.id, switch (mode) {
        MusicPlayMode.sequential => 'three',
        MusicPlayMode.repeatOne => 'three',
        MusicPlayMode.repeatAll => 'one',
        MusicPlayMode.shuffle => isNot('three'),
      });
      expect(engines.length, mode == MusicPlayMode.sequential ? 1 : 2);
    });
  }
}
