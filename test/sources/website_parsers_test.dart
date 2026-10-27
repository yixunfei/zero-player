import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/catalog/data/mac_cms_html_parser.dart';
import 'package:zero_player/features/live/data/tonkiang_service.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/sources/data/catalog_parser.dart';

void main() {
  final base = Uri.parse('https://example.test/');
  test('HTML detail preserves episodes and deduplicates shortcuts', () {
    final item = MacCmsHtmlParser('site', base).detail('''
      <h1>测试剧</h1><div class=module-tab-item>高清</div>
      <a href=/vodplay/12-1-1.html><span>第1集</span></a>
      <a href=/vodplay/12-1-1.html>立即播放</a>
      <a href=/vodplay/12-1-2.html>第2集</a>
      <a href=/vodplay/99-1-1.html>推荐影片</a>
    ''', '12');
    expect(item.title, '测试剧');
    expect(item.lines.single.episodes.length, 2);
    expect(item.lines.single.episodes.first.requiresResolution, isTrue);
    expect(item.lines.single.episodes.first.uri.path, '/vodplay/12-1-1.html');
  });
  test('player data supports encoding without executing scripts', () {
    const media = 'https://media.test/video.m3u8?x=a%20b';
    for (final mode in [0, 1, 2]) {
      final value = mode == 0
          ? media
          : mode == 1
          ? Uri.encodeComponent(media)
          : base64.encode(utf8.encode(Uri.encodeComponent(media)));
      final text =
          'var player_aaaa=${jsonEncode({'encrypt': mode, 'url': value, 'note': '} inside string'})};evil();';
      expect(parseMacCmsPlayer(text, base).toString(), media);
    }
    for (final value in [
      'javascript:alert(1)',
      'https://parser.test/play.html',
    ]) {
      expect(
        () => parseMacCmsPlayer(
          'var player_a=${jsonEncode({'url': value})}',
          base,
        ),
        throwsFormatException,
      );
    }
  });
  liveParserTests(base);
}

void liveParserTests(Uri base) {
  test('Tonkiang consumes stream text, not player or advertisement links', () {
    final result = TonkiangService.parse('''
      <a href=https://ads.test/>广告</a>
      <div class=resultplus><div class=channel><div class=tip>CCTV1</div></div>
      <tba class=mjxj>https://media.test/live.m3u8?a=1&amp;b=2</tba></div>
      <a href='/?keyword=CCTV1&amp;page=2'> &gt;&gt; </a>
    ''', TonkiangService.origin);
    expect(result.channels.single.name, 'CCTV1');
    expect(result.channels.single.urls.single.queryParameters['b'], '2');
    expect(result.nextPage!.queryParameters['page'], '2');
    expect(
      () => TonkiangService.parse('<div class=g-recaptcha></div>', base),
      throwsException,
    );
  });
  test('TXT list groups alternates and rejects HTML and HLS', () {
    final text = [
      '央视,#genre#',
      'CCTV1,https://a.test/live',
      'CCTV1,https://b.test/live',
      'bad,file:///secret',
    ].join(String.fromCharCode(10));
    final channels = parseLivePlaylist(text, base, 'list');
    expect(channels.single.group, '央视');
    expect(channels.single.urls.length, 2);
    expect(
      () => parseLivePlaylist('<html>error</html>', base, 'x'),
      throwsFormatException,
    );
    expect(
      () => parseLivePlaylist(
        '#EXTM3U${String.fromCharCode(10)}#EXT-X-TARGETDURATION:6',
        base,
        'x',
      ),
      throwsFormatException,
    );
  });
  test(
    'TVBox extracts independent live lists and diagnoses executable sources',
    () {
      final catalog = const JsonSourceCatalogParser().parse(
        jsonEncode({
          'sites': [
            {'name': 'spider', 'type': 3, 'api': 'csp_Test'},
          ],
          'lives': [
            {
              'name': 'TV',
              'type': 0,
              'url': 'https://tv.test/list.txt',
              'ua': 'Player',
            },
            {'name': 'script', 'type': 3, 'api': 'csp_Live'},
            {
              'name': 'click',
              'url': 'https://tv.test/js',
              'click': 'execute()',
            },
          ],
        }),
        base,
      );
      expect(catalog.sources, isEmpty);
      expect(catalog.lives.single.headers['User-Agent'], 'Player');
      expect(catalog.diagnostics.length, 3);
    },
  );
}
