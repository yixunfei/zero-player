import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/data/music_recommendations.dart';

void main() {
  for (final homepage in musicHomepages.keys) {
    test(
      'public discovery metadata: $homepage',
      () async {
        final db = AppDatabase.memory();
        final http = MediaHttpClient();
        final feed = MusicRecommendations(DocumentClient(http), db);
        addTearDown(() async {
          await feed.close();
          http.close();
          await db.close();
        });
        final watch = Stopwatch()..start();
        await feed.load(homepage, refresh: true);
        expect(feed.showingFallback, isFalse, reason: feed.notice);
        expect(feed.notice, isNull);
        expect(feed.items.length, greaterThanOrEqualTo(10));
        expect(feed.items.every((item) => item.title.isNotEmpty), isTrue);
        // Metadata success does not assert audio playback or device performance.
        debugPrint(
          '$homepage: ${feed.items.length} items in ${watch.elapsedMilliseconds} ms',
        );
      },
      skip: !const bool.fromEnvironment('RUN_MUSIC_ONLINE'),
    );
  }
}
