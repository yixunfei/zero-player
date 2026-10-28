import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/epg_parser.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/data/m3u_parser.dart';

import '../../test_support/http_test_server.dart';

void main() {
  _playlistTests();
  _epgParserTests();
  _epgRefreshTests();
}

void _playlistTests() {
  test('reimport without EPG preserves the configured EPG URL', () async {
    final db = AppDatabase.memory();
    final http = MediaHttpClient();
    addTearDown(db.close);
    addTearDown(http.close);
    final live = LiveRepository(db, DocumentClient(http));
    final uri = Uri.parse('https://tv.test/list');
    await live.importText(
      'TV',
      uri,
      'TV,https://media.test/old',
      epg: Uri.parse('https://tv.test/epg.xml'),
    );
    await live.importText('TV', uri, 'TV,https://media.test/new');
    expect((await live.lists()).single['epg_url'], 'https://tv.test/epg.xml');
    expect((await live.channels()).single.urls.single.path, '/new');
  });

  test('M3U and TXT retain newly introduced URLs at the alternative limit', () {
    final base = Uri.parse('https://media.test/list');
    final addresses = List.generate(
      101,
      (index) => 'https://media.test/$index',
    ).join('\n');
    final m3u = '#EXTM3U\n#EXTINF:-1,TV\n$addresses';
    final urls = parseM3u(m3u, base, 'test').single.urls;
    expect(urls.length, 100);
    expect(urls.last.path, '/100');
    expect(urls.any((uri) => uri.path == '/0'), isFalse);
    final txt = List.generate(
      101,
      (index) => 'TV,https://media.test/$index',
    ).join('\n');
    expect(parseLivePlaylist(txt, base, 'test').single.urls, urls);
  });

  test(
    'TXT separates alternate absolute URLs while preserving URL fragments',
    () {
      final urls = parseLivePlaylist(
        'TV,https://media.test/a#token#https://media.test/b#part',
        Uri.parse('https://media.test/list'),
        'test',
      ).single.urls;
      expect(urls.map((uri) => uri.toString()), [
        'https://media.test/a#token',
        'https://media.test/b#part',
      ]);
    },
  );
}

void _epgParserTests() {
  test(
    'event parsing preserves the first title, entities, CDATA and UTC offsets',
    () {
      final programs = parseEpg(
        '<tv><programme start="20261028120000 +0800" stop="20261028130000 +0800" channel="tv"><title>A &amp; <![CDATA[B]]><b>C</b></title><title>Other</title></programme></tv>',
      );
      expect(programs.single.title, 'A & BC');
      expect(programs.single.start, DateTime.utc(2026, 10, 28, 4));
      expect(() => parseEpg('<tv><programme></tv>'), throwsA(anything));
      expect(() => parseEpg('<!DOCTYPE tv><tv/>'), throwsFormatException);
    },
  );

  test(
    'background parser filters outside the retained schedule window',
    () async {
      final programs = await parseEpgInBackground(
        '<tv><programme start="20261028120000" stop="20261028130000" channel="current"><title>Current</title></programme><programme start="20260101120000" stop="20260101130000" channel="old"><title>Old</title></programme></tv>',
        DateTime.utc(2026, 10, 28),
      );
      expect(programs.single.channelId, 'current');
    },
  );

  test(
    'programme limit includes malformed entries rather than just accepted entries',
    () {
      final programs = List.filled(100001, '<programme/>').join();
      final xml = '<tv>$programs</tv>';
      expect(() => parseEpg(xml), throwsFormatException);
    },
  );
}

void _epgRefreshTests() {
  test(
    'EPG batches replace all rows and parsing failure retains previous rows',
    () async {
      final now = DateTime.now().toUtc();
      final start = _xmlTime(now.subtract(const Duration(hours: 1)));
      final stop = _xmlTime(now.add(const Duration(hours: 1)));
      final programs = List.generate(
        600,
        (index) =>
            '<programme start="$start" stop="$stop" channel="$index"><title>Program $index</title></programme>',
      ).join();
      var xml = '<tv>$programs</tv>';
      final server = await HttpTestServer.start(
        (request) => request.response.write(xml),
      );
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(db.close);
      addTearDown(server.close);
      addTearDown(http.close);
      final live = LiveRepository(db, DocumentClient(http));
      await live.refreshEpg(server.baseUri);
      expect(
        (await db.rows(
          'SELECT COUNT(*) AS count FROM epg_programs',
        )).single['count'],
        600,
      );
      xml = '<tv><programme></tv>';
      await expectLater(live.refreshEpg(server.baseUri), throwsA(anything));
      expect(
        (await db.rows(
          'SELECT COUNT(*) AS count FROM epg_programs',
        )).single['count'],
        600,
      );
    },
  );
}

String _xmlTime(DateTime time) {
  final digits = time
      .toIso8601String()
      .replaceAll(RegExp('[-:T]'), '')
      .split('.')
      .first;
  return '$digits +0000';
}
