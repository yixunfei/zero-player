import 'dart:async';
import 'dart:convert';
import '../../test_support/http_test_server.dart';
import '../../test_support/music_fixture.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/music/application/music_controller.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import '../../test_support/fake_player_engine.dart';
import '../../test_support/supervision_fixture.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

MusicTrack song(String id) => MusicTrack(
  id: id,
  title: id,
  artist: 'artist',
  url: Uri.parse('https://media.example/$id.mp3'),
  fetchedAt: DateTime.now(),
);

void main() {
  _safetyTests();
  _playbackTests();
  _failureRecoveryTests();
  _audioCoordinationTests();
}

void _safetyTests() {
  test(
    'a timed out setup cannot open a song when its future completes later',
    () async {
      final release = Completer<void>();
      var created = false;
      final http = MediaHttpClient();
      final player = MusicController(
        MusicRepository(MyFreeMp3Client(DocumentClient(http))),
        () {
          created = true;
          return FakePlayerEngine();
        },
        beforePlay: () => release.future,
        operationTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        await player.close();
        http.close();
      });
      await player.select([song('late')], 0);
      expect(player.loading, isFalse);
      expect(player.error, isNotNull);
      release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(created, isFalse);
    },
  );
  test(
    'updated supervision rules hide songs and stop active playback',
    () async {
      final fixture = SupervisionFixture();
      await fixture.configure();
      await fixture.authorized(
        SensitiveOperation.supervision,
        () => fixture.guard.setEnabled(true),
      );
      final http = MediaHttpClient();
      final repository = MusicRepository(
        MyFreeMp3Client(DocumentClient(http)),
        policy: fixture.policy,
      );
      final player = MusicController(repository, () => FakePlayerEngine());
      addTearDown(() async {
        await player.close();
        http.close();
        await fixture.close();
      });
      await player.select([song('restricted')], 0);
      await fixture.authorized(
        SensitiveOperation.supervision,
        () => fixture.guard.updateRules(
          SupervisionRules(keywords: ['restricted']),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.allowed(song('restricted')), isFalse);
      expect(player.active, isFalse);
      await expectLater(
        repository.search('restricted'),
        throwsA(isA<ContentBlocked>()),
      );
    },
  );
}

void _playbackTests() {
  test('queue completion, seeking, pause and stop', () async {
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
    await player.select([song('first'), song('second')], 0);
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isTrue);
    await player.seek(const Duration(seconds: 10));
    expect(engines.first.seeks.single, const Duration(seconds: 10));
    await player.pause();
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isFalse);
    await player.toggle();
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isTrue);
    engines.first.emit(const PlaybackSnapshot(completed: true));
    for (var i = 0; i < 30 && player.selected?.id != 'second'; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
    expect(player.selected?.id, 'second');
    expect(engines.last.opens, 1);
    await player.stop();
    expect(player.active, isFalse);
  });
  test('stop and close interrupt setup without a late native open', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final engine = FakePlayerEngine(
      onVolume: (_) {
        entered.complete();
        return release.future;
      },
    );
    final http = MediaHttpClient();
    final player = MusicController(
      MusicRepository(MyFreeMp3Client(DocumentClient(http))),
      () => engine,
    );
    final opening = player.select([song('cancelled')], 0);
    await entered.future;
    await player.stop().timeout(const Duration(seconds: 2));
    release.complete();
    await opening;
    expect(engine.opens, 0);
    await player.close();
    http.close();
  });
}

void _audioCoordinationTests() {
  test(
    'music, radio and video pause each other through application services',
    () async {
      final root = await Directory.systemTemp.createTemp('music-isolated-');
      final music = FakePlayerEngine();
      final radio = FakePlayerEngine();
      final services = AppServices.scoped(
        root,
        AppDatabase.memory(),
        musicEngine: () => music,
        radioEngine: () => radio,
      );
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      await services.settings.load();
      await services.radioPlayer.select(
        LiveChannel(
          id: 'radio',
          listId: 'test',
          name: '广播',
          urls: [Uri.parse('https://example.com/radio.mp3')],
        ),
      );
      await services.musicPlayer.select([song('music')], 0);
      await Future<void>.delayed(Duration.zero);
      expect(radio.snapshot.playing, isFalse);
      expect(music.snapshot.playing, isTrue);
      await services.radioPlayer.toggle();
      await Future<void>.delayed(Duration.zero);
      expect(music.snapshot.playing, isFalse);
      expect(radio.snapshot.playing, isTrue);
      await services.musicPlayer.toggle();
      await services.pauseAudioForVideo();
      await Future<void>.delayed(Duration.zero);
      expect(music.snapshot.playing, isFalse);
      expect(radio.snapshot.playing, isFalse);
    },
  );
}

void _failureRecoveryTests() {
  for (final nativeError in [true, false]) {
    test(
      'failed ${nativeError ? 'native playback' : 'seek'} retires engine and retries at saved position',
      () async {
        final server = await HttpTestServer.start((request) {
          request.response.write(
            request.uri.path == '/api/signing/bootstrap'
                ? jsonEncode({
                    'key_id': 'id',
                    'signing_key': 'key',
                    'expires_at':
                        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600,
                  })
                : musicFixture(),
          );
        });
        final http = MediaHttpClient(allowPrivateNetworks: true);
        final engines = <FakePlayerEngine>[];
        final player = MusicController(
          MusicRepository(
            MyFreeMp3Client(DocumentClient(http), endpoint: server.baseUri),
          ),
          () {
            final engine = FakePlayerEngine(
              onSeek: (position) async {
                if (!nativeError &&
                    engines.length == 1 &&
                    position.inSeconds == 9) {
                  throw StateError('seek failed');
                }
              },
            );
            engines.add(engine);
            return engine;
          },
        );
        addTearDown(() async {
          await player.close();
          http.close();
          await server.close();
        });
        await player.select([song('-12_34'), song('second')], 0);
        await player.seek(const Duration(seconds: 7));
        await Future<void>.delayed(Duration.zero);
        if (nativeError) {
          engines.first.failures.add('decoder failed');
          // A late completion from the failed engine must not skip the song.
          engines.first.emit(const PlaybackSnapshot(completed: true));
        } else {
          await player.seek(const Duration(seconds: 9));
        }
        for (var i = 0; i < 30 && player.error == null; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(player.error, isNotNull);
        expect(player.playing, isFalse);
        expect(player.loading, isFalse);
        expect(player.snapshot.position, const Duration(seconds: 7));
        expect(player.selected?.id, '-12_34');
        await player.toggle();
        await Future<void>.delayed(Duration.zero);
        expect(engines, hasLength(2));
        expect(engines.last.seeks.single, const Duration(seconds: 7));
        expect(player.playing, isTrue);
        expect(player.error, isNull);
      },
    );
  }
}
