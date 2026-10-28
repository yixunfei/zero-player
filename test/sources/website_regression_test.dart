import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/mac_cms_html_parser.dart';
import 'package:zero_player/features/catalog/data/mac_cms_html_provider.dart';
import 'package:zero_player/features/catalog/data/website_transport.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'CMS subdirectory and endpoint authentication survive generated URLs',
    () async {
      final seen = <Uri>[];
      final server = await HttpTestServer.start((request) {
        seen.add(request.uri);
        if (request.uri.path.contains('voddetail')) {
          request.response.write(
            '<h1>测试</h1><a href="/cms/vodplay/12-1-1.html">第1集</a>',
          );
        } else {
          request.response.write(
            '<form action="/cms/vodsearch/"></form><a href="/cms/voddetail/12.html">测试</a>',
          );
        }
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(http.close);
      addTearDown(server.close);
      final source = VideoSource(
        id: 'html',
        name: 'html',
        endpoint: server.baseUri.resolve('cms/?token=private'),
      );
      final provider = MacCmsHtmlProvider(
        WebsiteTransport(source, DocumentClient(http)),
      );
      await provider.search('中文', page: 2);
      final detail = await provider.detail('12');
      expect(seen.first.path, '/cms/vodsearch/-------------.html');
      expect(seen.first.queryParameters, {
        'token': 'private',
        'wd': '中文',
        'page': '2',
      });
      expect(seen.last.path, '/cms/voddetail/12.html');
      expect(seen.last.queryParameters['token'], 'private');
      expect(
        detail.lines.single.episodes.single.uri.path,
        '/cms/vodplay/12-1-1.html',
      );
    },
  );

  test('line names match stable group identifiers instead of DOM order', () {
    final item = MacCmsHtmlParser('s', Uri.parse('https://site.test/')).detail(
      '''
      <h1>测试</h1>
      <div class="module-tab-item" data-dropdown-value="2">线路乙</div>
      <div class="module-tab-item" data-dropdown-value="1">线路甲</div>
      <a href="/vodplay/12-1-1.html">第1集</a>
      <a href="/vodplay/12-2-1.html">第1集</a>
    ''',
      '12',
    );
    expect(item.lines.map((line) => line.name), ['线路甲', '线路乙']);
  });

  test('non-object player JSON is rejected as a format error', () {
    for (final value in [
      '[]',
      'null',
      '"text"',
      '[{"url":"https://media.test/video.mp4"}]',
    ]) {
      expect(
        () => parseMacCmsPlayer(
          'var player_a=$value;',
          Uri.parse('https://site.test/'),
        ),
        throwsFormatException,
      );
    }
  });
}
