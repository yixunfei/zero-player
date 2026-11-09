import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/application/music_browser.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';

void main() {
  late AppDatabase db;
  late MediaHttpClient http;
  MusicBrowser create() => MusicBrowser(
    MusicRepository(MyFreeMp3Client(DocumentClient(http))),
    db: db,
  );
  setUp(() {
    db = AppDatabase.memory();
    http = MediaHttpClient();
  });
  tearDown(() async {
    http.close();
    await db.close();
  });
  _restoreTests(create, () => db);
  _earlySelectionTest(create, () => db);

  test(
    'aggregated search is selected and MY FREE MP3 is favorited initially',
    () async {
      final browser = create();
      await browser.load();
      expect(browser.provider, 'all');
      expect(browser.favoriteProviders, {'myfreemp3'});
      expect(browser.orderedProviders.first, 'myfreemp3');
      expect(() => browser.favoriteProviders.clear(), throwsUnsupportedError);
      await browser.close();
    },
  );

  test(
    'favorites and priority survive restart without changing selection',
    () async {
      var browser = create();
      await browser.load();
      browser.selectProvider('netease');
      browser.setFavorite('myfreemp3', false);
      browser.setFavorite('flacHi', true);
      browser.setFavorite('audius', true);
      browser.setFavorite('unknown', true);
      await browser.close();
      browser = create();
      await browser.load();
      expect(browser.provider, 'netease');
      expect(browser.favoriteProviders, {'audius', 'flacHi'});
      expect(browser.orderedProviders.take(2), ['audius', 'flacHi']);
      browser.setFavorite('audius', false);
      browser.setFavorite('flacHi', false);
      await browser.close();
      browser = create();
      await browser.load();
      expect(browser.favoriteProviders, isEmpty);
      await browser.close();
    },
  );
}

void _earlySelectionTest(
  MusicBrowser Function() create,
  AppDatabase Function() database,
) {
  test(
    'editing before explicit load preserves the new channel and other favorites',
    () async {
      await database().write('INSERT INTO app_meta VALUES(?,?)', [
        'music_provider',
        jsonEncode('audius'),
      ]);
      await database().write('INSERT INTO app_meta VALUES(?,?)', [
        'music_source_favorites',
        jsonEncode(['myfreemp3', 'flacHi']),
      ]);
      final browser = create();
      browser.setFavorite('myfreemp3', false);
      browser.selectProvider('netease');
      await browser.load();
      expect(browser.provider, 'netease');
      expect(browser.favoriteProviders, {'flacHi'});
      await browser.close();
    },
  );
}

void _restoreTests(
  MusicBrowser Function() create,
  AppDatabase Function() database,
) {
  test(
    'edits during restore merge with saved favorites even on immediate close',
    () async {
      await database().write('INSERT INTO app_meta VALUES(?,?)', [
        'music_source_favorites',
        jsonEncode(['myfreemp3', 'audius']),
      ]);
      var browser = create();
      final restore = browser.load();
      browser.selectProvider('netease');
      browser.setFavorite('myfreemp3', false);
      browser.setFavorite('flacHi', true);
      await browser.close();
      await restore;
      browser = create();
      await browser.load();
      expect(browser.favoriteProviders, {'audius', 'flacHi'});
      expect(browser.provider, 'netease');
      await browser.close();
    },
  );

  test(
    'corrupt favorites do not lose a valid selection or block search defaults',
    () async {
      await database().write('INSERT INTO app_meta VALUES(?,?)', [
        'music_provider',
        jsonEncode('audius'),
      ]);
      for (final value in ['invalid json', '{}', '["audius",42]']) {
        await database().write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
          'music_source_favorites',
          value,
        ]);
        final browser = create();
        await browser.load();
        expect(browser.provider, 'audius');
        expect(browser.favoriteProviders, {'myfreemp3'});
        await browser.close();
      }
    },
  );

  test(
    'obsolete favorites are ignored without restoring cancelled defaults',
    () async {
      await database().write('INSERT INTO app_meta VALUES(?,?)', [
        'music_source_favorites',
        jsonEncode(['retired-source', 'flacHi']),
      ]);
      final browser = create();
      await browser.load();
      expect(browser.favoriteProviders, {'flacHi'});
      expect(browser.orderedProviders.first, 'flacHi');
      await browser.close();
    },
  );
}
