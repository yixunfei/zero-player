import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/application/music_controller.dart';
import 'package:zero_player/features/music/data/music_library.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/fake_player_engine.dart';
import '../../test_support/http_test_server.dart';
import '../../test_support/music_fixture.dart';
import '../../test_support/supervision_fixture.dart';

MusicTrack song(String id) => MusicTrack(
  id: id,
  title: id,
  artist: '',
  url: Uri.parse('https://example.com/$id.mp3'),
  fetchedAt: DateTime.now(),
);

void main() {
  _editingTests();
  _policyTest();
  _retryTest();
}

void _editingTests() {
  test(
    'queue edits deduplicate songs and preserve active engine and progress',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.player.select([song('a'), song('b'), song('b'), song('c')], 0);
      await f.player.seek(const Duration(seconds: 8));
      await f.player.enqueue(song('d'), playNext: true);
      await f.player.enqueue(song('b'));
      expect(f.player.queue.map((t) => t.id), ['a', 'd', 'b', 'c']);
      f.player.moveInQueue(song('a').key, 2);
      expect(f.player.index, 2);
      expect(f.player.selected?.id, 'a');
      await f.player.removeFromQueue(song('d').key);
      expect(f.player.index, 1);
      expect(f.engines, hasLength(1));
      expect(f.player.snapshot.position, const Duration(seconds: 8));
      f.player.clearUpcoming();
      expect(f.player.queue.single.id, 'a');
      expect(() => f.player.queue.add(song('x')), throwsUnsupportedError);
    },
  );
  test(
    'removing the current song advances and removing the last stops',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.player.select([song('a'), song('b'), song('c')], 1);
      await f.player.removeFromQueue(song('b').key);
      expect(f.player.selected?.id, 'c');
      expect(f.engines, hasLength(2));
      await f.player.removeFromQueue(song('a').key);
      await f.player.removeFromQueue(song('c').key);
      expect(f.player.active, isFalse);
      expect(f.player.queue, isEmpty);
    },
  );
  test(
    'repeat-all previous wraps and bounded queue rejects extra songs',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.player.setMode(MusicPlayMode.repeatAll);
      await f.player.select([song('a'), song('b')], 0);
      await f.player.previous();
      expect(f.player.selected?.id, 'b');
      await f.player.select([for (var i = 0; i < 500; i++) song('$i')], 0);
      await expectLater(
        f.player.enqueue(song('overflow')),
        throwsFormatException,
      );
      expect(f.player.queue, hasLength(500));
    },
  );
}

void _policyTest() {
  test(
    'newly blocked upcoming songs are removed without interrupting current playback',
    () async {
      final guard = SupervisionFixture();
      await guard.configure();
      await guard.authorized(
        SensitiveOperation.supervision,
        () => guard.guard.setEnabled(true),
      );
      final f = _Fixture(guard);
      addTearDown(() async {
        await f.close();
        await guard.close();
      });
      await f.player.select([
        song('allowed'),
        song('blocked'),
        song('next'),
      ], 0);
      await f.player.seek(const Duration(seconds: 8));
      await guard.authorized(
        SensitiveOperation.supervision,
        () => guard.guard.updateRules(SupervisionRules(keywords: ['blocked'])),
      );
      expect(f.player.queue.map((t) => t.id), ['allowed', 'next']);
      expect(f.player.snapshot.position, const Duration(seconds: 8));
      expect(f.engines, hasLength(1));
      f.engines.single.emit(const PlaybackSnapshot(completed: true));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(f.player.selected?.id, 'next');
      expect(f.engines, hasLength(2));
    },
  );
}

void _retryTest() {
  test(
    'refresh after a stream error restores the last known position',
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
          final engine = FakePlayerEngine();
          engines.add(engine);
          return engine;
        },
      );
      addTearDown(() async {
        await player.close();
        http.close();
        await server.close();
      });
      await player.select([song('-12_34')], 0);
      await player.seek(const Duration(seconds: 9));
      engines.single.failures.add('connection lost');
      await Future<void>.delayed(Duration.zero);
      await player.retry();
      expect(player.error, isNull);
      expect(engines.last.seeks, [const Duration(seconds: 9)]);
    },
  );
}

final class _Fixture {
  _Fixture([SupervisionFixture? guard]) {
    player = MusicController(
      MusicRepository(
        MyFreeMp3Client(DocumentClient(http)),
        policy: guard?.policy,
      ),
      () {
        final engine = FakePlayerEngine();
        engines.add(engine);
        return engine;
      },
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
