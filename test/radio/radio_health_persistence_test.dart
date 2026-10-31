import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/radio/data/radio_snapshot.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test('same-list radio aliases retain all alternatives under a unique ID', () {
    final snapshot = RadioSnapshot(
      text:
          '#EXTM3U\n#EXTINF:-1,CCTV1\nhttps://a.test/a\n#EXTINF:-1,(SD)CCTV1\nhttps://b.test/b',
      base: Uri.parse('https://list.test/'),
      updatedAt: DateTime.now(),
    );
    final stations = snapshot.stations(
      RadioSubscription(name: 'test', url: Uri.parse('https://list.test/')),
    );
    expect(stations, hasLength(1));
    expect(stations.single.urls, hasLength(2));
  });
  test(
    'radio health survives reload; changing routes invalidates only evidence',
    () async {
      var payload = '#EXTM3U\n#EXTINF:-1,电台\nhttps://media.test/a.mp3';
      final server = await HttpTestServer.start(
        (r) => r.response.write(payload),
      );
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final repository = RadioRepository(
        db,
        DocumentClient(http),
        source: server.baseUri,
      );
      addTearDown(() async {
        await repository.close();
        http.close();
        await server.close();
        await db.close();
      });
      final station = (await repository.load()).stations.single;
      final health = LiveHealthRepository(db);
      await health.record(
        station,
        LiveHealth(
          availability: LiveAvailability.responding,
          preferredUrl: station.urls.single.toString(),
          latencyMs: 12,
        ),
      );
      await health.setEnabled([station.id], false);
      var saved = (await repository.load()).stations.single;
      expect(saved.health.enabled, isFalse);
      expect(saved.health.availability, LiveAvailability.responding);
      payload = payload.replaceAll('.mp3', '-new.mp3');
      saved = (await repository.load(refresh: true)).stations.single;
      expect(saved.health.enabled, isFalse);
      expect(saved.health.availability, LiveAvailability.unknown);
      expect(saved.health.preferredUrl, isNull);
    },
  );
}
