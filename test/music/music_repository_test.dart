import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/application/music_browser.dart';
import 'package:zero_player/features/music/data/music_parser.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import '../../test_support/http_test_server.dart';
import '../../test_support/music_fixture.dart';

void main() {
  _parserTests();
  _protocolTests();
  _browserTests();
}

void _parserTests() {
  test('parses site markup, plain text, duration and pagination', () {
    final result = parseMusicSearch(
      musicFixture(title: '<b>晴天</b> &amp; 风'),
      query: '周杰伦',
      page: 1,
    );
    expect(result.tracks.single.title, '晴天 & 风');
    expect(result.tracks.single.artist, '周杰伦');
    expect(result.tracks.single.id, '-12_34');
    expect(
      result.tracks.single.duration,
      const Duration(minutes: 4, seconds: 29),
    );
    expect(result.hasNext, isTrue);
    expect(
      () => parseMusicSearch('<html>Challenge</html>', query: 'a', page: 1),
      throwsFormatException,
    );
    expect(
      parseMusicSearch(
        '<div class="search-empty-state">No songs</div>',
        query: 'a',
        page: 1,
      ).tracks,
      isEmpty,
    );
  });
  test('unsafe rows are rejected and legacy CDN spelling is repaired', () {
    for (final url in [
      'file:///C:/x.mp3',
      'http://127.0.0.1/a.mp3',
      'https://user:password@example.com/x',
      'javascript:alert(1)',
    ]) {
      expect(
        () => parseMusicSearch(musicFixture(url: url), query: 'a', page: 1),
        throwsFormatException,
      );
    }
    expect(
      parseMusicSearch(
        musicFixture(url: 'https://cs1-12v4s1.myfreemp3.ink/a.mp3'),
        query: 'a',
        page: 1,
      ).tracks.single.url.host,
      'cs1-12v4.s1.myfreemp3.ink',
    );
  });
}

void _protocolTests() {
  test(
    'signs unicode searches and pagination, renews a rejected key once',
    () async {
      var bootstraps = 0;
      var searches = 0;
      final server = await HttpTestServer.start((request) {
        expect(request.headers.value('origin'), 'https://myfreemp3.ink');
        expect(request.headers.value('x-requested-with'), 'XMLHttpRequest');
        if (request.uri.path == '/api/signing/bootstrap') {
          bootstraps++;
          request.response.write(
            jsonEncode({
              'key_id': 'key-$bootstraps',
              'signing_key': 'temporary-key',
              'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600,
            }),
          );
          return;
        }
        searches++;
        expect(Uri.decodeComponent(request.uri.path), '/search/周杰伦');
        expect(request.uri.queryParameters['page'], '2');
        final stamp = request.headers.value('x-api-ts');
        final message =
            '$stamp\nGET\n${Uri.decodeComponent(request.uri.path)}\n?${request.uri.query}';
        expect(
          request.headers.value('x-api-sig'),
          Hmac(
            sha256,
            utf8.encode('temporary-key'),
          ).convert(utf8.encode(message)).toString(),
        );
        expect(request.headers.value('authorization'), isNull);
        if (searches == 1) {
          request.response.statusCode = 403;
          return;
        }
        request.response.headers.contentType = ContentType.html;
        request.response.write(musicFixture(next: false));
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(() async {
        http.close();
        await server.close();
      });
      final repository = MusicRepository(
        MyFreeMp3Client(DocumentClient(http), endpoint: server.baseUri),
      );
      final result = await repository.search('周杰伦', page: 2);
      expect(result.tracks.single.title, '晴天');
      expect(result.hasNext, isFalse);
      expect(bootstraps, 2);
      expect(searches, 2);
    },
  );
}

void _browserTests() {
  test(
    'superseded browser requests never replace newer search results',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final server = await HttpTestServer.start((request) async {
        if (request.uri.path == '/api/signing/bootstrap') {
          request.response.write(
            jsonEncode({
              'key_id': 'k',
              'signing_key': 'secret',
              'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600,
            }),
          );
        } else if (request.uri.path.endsWith('/old')) {
          entered.complete();
          await release.future;
          request.response.write(musicFixture(title: 'old'));
        } else {
          request.response.write(musicFixture(title: 'new'));
        }
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final browser = MusicBrowser(
        MusicRepository(
          MyFreeMp3Client(DocumentClient(http), endpoint: server.baseUri),
        ),
      );
      addTearDown(() async {
        browser.dispose();
        http.close();
        await server.close();
      });
      final old = browser.search('old');
      await entered.future;
      await browser.search('new');
      release.complete();
      await old;
      expect(browser.result.tracks.single.title, 'new');
      expect(browser.query, 'new');
    },
  );
}
