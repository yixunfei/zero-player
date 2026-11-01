import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/application/music_controller.dart';
import 'package:zero_player/features/music/application/music_open_api.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  test(
    'opt-in LX status endpoint filters fields and rejects browser/control requests',
    () async {
      final http = MediaHttpClient();
      final engine = FakePlayerEngine();
      final player = MusicController(
        MusicRepository(MyFreeMp3Client(DocumentClient(http))),
        () => engine,
      );
      final api = MusicOpenApi(player);
      final client = HttpClient();
      addTearDown(() async {
        await api.close();
        await player.close();
        client.close(force: true);
        http.close();
      });
      expect(api.address, isNull);
      await api.start();
      await player.select([
        MusicTrack(
          id: 'test',
          title: 'Song',
          artist: 'Artist',
          url: Uri.parse('https://example.com/a.mp3'),
          fetchedAt: DateTime.now(),
        ),
      ], 0);
      await Future<void>.delayed(Duration.zero);
      final response = await (await client.getUrl(
        Uri.parse('${api.address}/status?filter=name,singer,bogus'),
      )).close();
      expect(jsonDecode(await utf8.decoder.bind(response).join()), {
        'name': 'Song',
        'singer': 'Artist',
      });
      final browser = await client.getUrl(Uri.parse('${api.address}/status'));
      browser.headers.set('Origin', 'https://evil.example');
      final rejected = await browser.close();
      expect(rejected.statusCode, 403);
      await rejected.drain<void>();
      final control = await (await client.getUrl(
        Uri.parse('${api.address}/play'),
      )).close();
      expect(control.statusCode, 404);
      await control.drain<void>();
      final stream = await (await client.getUrl(
        Uri.parse('${api.address}/subscribe-player-status?filter=name'),
      )).close();
      var collected = '';
      final first = await utf8.decoder
          .bind(stream)
          .map((chunk) => collected += chunk)
          .firstWhere(
            (text) => text.contains('event: name') && text.contains('"Song"'),
          )
          .timeout(const Duration(seconds: 3));
      expect(first, contains('event: name'));
      expect(first, contains('"Song"'));
      await api.stop();
      expect(api.address, isNull);
    },
  );
}
