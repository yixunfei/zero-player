import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/application/music_browser.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  test(
    'filtered searches explain policy rejection without making a network request',
    () async {
      final guard = SupervisionFixture();
      await guard.configure();
      await guard.authorized(
        SensitiveOperation.supervision,
        () => guard.guard.setEnabled(true),
      );
      await guard.authorized(
        SensitiveOperation.supervision,
        () => guard.guard.updateRules(SupervisionRules(keywords: ['blocked'])),
      );
      final http = MediaHttpClient();
      final browser = MusicBrowser(
        MusicRepository(
          MyFreeMp3Client(DocumentClient(http)),
          policy: guard.policy,
        ),
      );
      addTearDown(() async {
        await browser.close();
        http.close();
        await guard.close();
      });
      await browser.search('blocked');
      expect(browser.error, contains('过滤规则'));
      expect(browser.result.tracks, isEmpty);
      expect(browser.loading, isFalse);
    },
  );
  test(
    'selected channel survives close and cannot be replaced by a late restore',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      MusicBrowser create() => MusicBrowser(
        MusicRepository(MyFreeMp3Client(DocumentClient(http))),
        db: db,
      );
      await db.write('INSERT INTO app_meta VALUES(?,?)', [
        'music_provider',
        jsonEncode('musicBox'),
      ]);
      final browser = create();
      final restore = browser.load();
      browser.selectProvider('qqmp3');
      await restore;
      expect(browser.provider, 'qqmp3');
      await browser.close();
      final reopened = create();
      await reopened.load();
      expect(reopened.provider, 'qqmp3');
      reopened.selectProvider('not-a-provider');
      expect(reopened.provider, 'qqmp3');
      await reopened.close();
      http.close();
      await db.close();
    },
  );
  test(
    'damaged or obsolete preferences keep the default channel usable',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(() async {
        http.close();
        await db.close();
      });
      for (final saved in [
        'invalid json',
        jsonEncode('retired-source'),
        '{}',
      ]) {
        await db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
          'music_provider',
          saved,
        ]);
        final browser = MusicBrowser(
          MusicRepository(MyFreeMp3Client(DocumentClient(http))),
          db: db,
        );
        await browser.load();
        expect(browser.provider, 'myfreemp3');
        await browser.close();
      }
    },
  );
}
