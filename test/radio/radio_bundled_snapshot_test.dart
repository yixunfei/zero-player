import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled successful snapshot supports first-launch offline browsing',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final repo = RadioRepository(db, DocumentClient(http));
      addTearDown(() async {
        await repo.close();
        http.close();
        await db.close();
      });
      final catalog = await repo.load();
      expect(catalog.stations.length, greaterThan(100));
      expect(catalog.stations.every((s) => s.urls.isNotEmpty), isTrue);
      expect(catalog.notice, isNull);
    },
  );
}
