import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_audit_defaults.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/data/playlist_epg.dart';

void main() {
  test(
    'packaged audit disables exact matches only and preserves personal state',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(() async {
        http.close();
        await db.close();
      });
      final url = Uri.parse('https://list.test/a');
      const text = 'One,https://media.test/a.ts';
      final live = LiveRepository(db, DocumentClient(http));
      await live.importText('TV', url, text);
      final channel = (await live.channels()).single;
      final defaults = LiveAuditDefaults(
        () async => jsonEncode({
          'results': [
            {
              'id': channel.id,
              'signature': channel.urls.join('|'),
              'availability': 'unavailable',
              'message': 'HTTP 404',
              'checkedAt': 1234,
              'languages': <String>[],
            },
          ],
        }),
      );
      final audited = LiveRepository(
        db,
        DocumentClient(http),
        defaults: defaults,
      );
      await audited.importText('TV', url, 'One,https://media.test/changed.ts');
      expect((await audited.channels()).single.health.enabled, isTrue);
      await audited.importText('TV', url, text);
      expect((await audited.channels()).single.health.enabled, isFalse);
      await LiveHealthRepository(db).setEnabled([channel.id], true);
      await audited.importText('TV', url, text);
      expect((await audited.channels()).single.health.enabled, isTrue);
    },
  );
  test('only explicit HTTP XMLTV declarations are used', () {
    final base = Uri.parse('https://list.test/list.m3u');
    expect(
      playlistEpg(
        '#EXTM3U x-tvg-url="https://epg.test/a.xml,https://epg.test/b.xml"',
        base,
      ).toString(),
      'https://epg.test/a.xml',
    );
    expect(playlistEpg('#EXTM3U x-tvg-url="file:///tmp/x"', base), isNull);
    expect(playlistEpg('#EXTM3U', base), isNull);
  });
}
