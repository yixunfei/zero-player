import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/application/music_controller.dart';
import 'package:zero_player/features/music/application/music_preflight.dart';
import 'package:zero_player/features/music/data/music_audio_probe.dart';
import 'package:zero_player/features/music/data/music_library.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_match.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';

import '../../test_support/fake_player_engine.dart';
import '../../test_support/http_test_server.dart';

MusicTrack _track(
  String provider, {
  String artist = '歌手',
  String title = '原曲',
}) => MusicTrack(
  id: '123',
  title: title,
  artist: artist,
  url: Uri.https('example.com', '/$provider.mp3'),
  provider: provider,
  fetchedAt: DateTime.now(),
);

MusicAudioSample _sample(MusicTrack track, int ms, {bool lossless = false}) => (
  track: track,
  latency: Duration(milliseconds: ms),
  lossless: lossless,
  mp3Kbps: 0,
);

void main() {
  test(
    'aggregation preserves versions and never joins songs with missing artists',
    () {
      final tracks = [
        _track('myfreemp3'),
        _track('netease'),
        _track('audius', title: '原曲 (Live)'),
        _track('kugou', artist: ''),
        _track('flacHi', artist: ''),
      ];
      expect(groupMusicTracks(tracks, enabled: true).map((g) => g.length), [
        2,
        1,
        1,
        1,
      ]);
      expect(groupMusicTracks(tracks, enabled: false), hasLength(5));
    },
  );

  test(
    'ranking uses finished samples immediately and honors the configured policy',
    () async {
      final http = MediaHttpClient();
      final fast = _track('myfreemp3');
      final lossless = _track('netease');
      final slow = Completer<MusicAudioSample>();
      final picker = MusicPreflight(
        _repository(http),
        probe: (track, _) async =>
            track == fast ? _sample(fast, 80) : slow.future,
      );
      addTearDown(() async {
        await picker.close();
        http.close();
      });
      final pending = picker.prepare(fast, alternatives: [lossless]);
      await Future<void>.delayed(Duration.zero);
      expect(picker.best(fast, 'quality')?.track, fast);
      slow.complete(_sample(lossless, 380, lossless: true));
      await pending;
      expect(picker.best(fast, 'fastest')?.track, fast);
      expect(picker.best(fast, 'quality')?.track, lossless);
      expect(picker.best(fast, 'balanced')?.track, lossless);
      picker.markFailed(lossless);
      expect(picker.best(fast, 'quality')?.track, fast);
    },
  );

  _controllerTests();
  _probeTest();
}

void _controllerTests() {
  test('queue addition is idle-safe and play next overrides shuffle', () async {
    final f = _PlayerFixture((track, _) async => _sample(track, 80));
    addTearDown(f.close);
    final first = _track('myfreemp3', artist: '');
    final next = _track('netease', artist: '');
    await f.player.enqueue(first);
    expect(f.engines, isEmpty);
    await f.player.toggle();
    await f.player.setMode(MusicPlayMode.shuffle);
    await f.player.enqueue(next, playNext: true);
    f.engines.single.emit(const PlaybackSnapshot(completed: true));
    await _until(() => f.player.selected == next && !f.player.loading);
    expect(f.player.queue.first, first);
    expect(f.engines, hasLength(2));
  });

  test(
    'continuous buffering switches to a tested source and resumes position',
    () async {
      final first = _track('myfreemp3');
      final alternate = _track('netease');
      final f = _PlayerFixture(
        (track, _) async => _sample(track, track == first ? 50 : 80),
      );
      addTearDown(f.close);
      await f.player.setAutoSwitchSource(true);
      f.player.prepareResults([
        [first, alternate],
      ]);
      await Future<void>.delayed(Duration.zero);
      await f.player.select(
        [first],
        0,
        variants: {
          first.key: [alternate],
        },
      );
      await f.player.seek(const Duration(seconds: 7));
      f.engines.single.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 7),
          duration: Duration(seconds: 30),
          buffering: true,
        ),
      );
      await _until(
        () => f.player.playingTrack == alternate && !f.player.loading,
      );
      expect(f.player.selected, first);
      expect(f.engines.last.seeks, [const Duration(seconds: 7)]);
      expect(f.player.error, isNull);
      await f.player.pause();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(f.engines, hasLength(2));
      expect(f.player.error, isNull);
    },
  );
  test(
    'a failed queued source is replaced with a ready matching version',
    () async {
      final first = _track('myfreemp3', title: '前一首', artist: '');
      final unavailable = _track('kugou');
      final alternate = _track('netease');
      final f = _PlayerFixture((track, _) async {
        if (track.key == unavailable.key) {
          throw const FormatException('unavailable');
        }
        return _sample(track, 80);
      });
      addTearDown(f.close);
      await f.player.setAutoSwitchSource(true);
      await f.player.select([first], 0);
      await f.player.enqueue(unavailable, alternatives: [alternate]);
      await Future<void>.delayed(Duration.zero);
      f.engines.single.emit(const PlaybackSnapshot(completed: true));
      await _until(() => f.player.selected == unavailable && !f.player.loading);
      expect(f.player.playingTrack, alternate);
      expect(f.engines, hasLength(2));
    },
  );
}

void _probeTest() {
  test(
    'audio precheck samples a range and rejects a successful HTML response',
    () async {
      final ranges = <String?>[];
      final server = await HttpTestServer.start((request) {
        ranges.add(request.headers.value('range'));
        if (request.uri.path == '/audio') {
          request.response.statusCode = 206;
          request.response.headers.set(
            'content-type',
            'application/octet-stream',
          );
          request.response.write('fLaCxxxx');
        } else if (request.uri.path == '/mp3') {
          request.response.headers.set('content-type', 'audio/mpeg');
          request.response.add([0xff, 0xfb, 0x90, 0x64]);
        } else {
          request.response.headers.set('content-type', 'text/html');
          request.response.write('<html>sign in</html>');
        }
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(() async {
        http.close();
        await server.close();
      });
      final track = _track('myfreemp3');
      final repository = _repository(http);
      final result = await probeMusicAudio(
        repository,
        track.withUrl(server.baseUri.resolve('/audio')),
        CancellationToken(),
      );
      expect(result.lossless, isTrue);
      final mp3 = await probeMusicAudio(
        repository,
        track.withUrl(server.baseUri.resolve('/mp3')),
        CancellationToken(),
      );
      expect(mp3.mp3Kbps, 128);
      await expectLater(
        probeMusicAudio(
          repository,
          track.withUrl(server.baseUri.resolve('/html')),
          CancellationToken(),
        ),
        throwsFormatException,
      );
      expect(ranges, List.filled(3, 'bytes=0-2047'));
    },
  );
}

MusicRepository _repository(MediaHttpClient http) =>
    MusicRepository(MyFreeMp3Client(DocumentClient(http)));

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue);
}

final class _PlayerFixture {
  _PlayerFixture(MusicProbe probe) {
    player = MusicController(
      _repository(http),
      () {
        final engine = FakePlayerEngine();
        engines.add(engine);
        return engine;
      },
      probe: probe,
      stallTimeout: const Duration(milliseconds: 65),
    );
  }

  final http = MediaHttpClient();
  final engines = <FakePlayerEngine>[];
  late final MusicController player;
  Future<void> close() async {
    await player.close();
    http.close();
  }
}
