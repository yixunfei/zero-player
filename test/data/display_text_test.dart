import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/text/display_text.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/cms_provider.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';

void main() {
  test(
    'highlight tags preserve contiguous Chinese names and decode entities',
    () {
      expect(displayText('<em>侠</em><em>探</em><em>杰克</em> 第一季'), '侠探杰克 第一季');
      expect(
        displayText('&lt;em&gt;侠探&lt;/em&gt;&nbsp;&#x6770;&#20811;'),
        '侠探 杰克',
      );
      expect(displayText('&amp;lt;em&amp;gt;电影&amp;lt;/em&amp;gt;'), '电影');
      expect(
        displayText('Tom &amp; Jerry &#39;2026&#39;'),
        "Tom & Jerry '2026'",
      );
      expect(displayText('2 < 3 > 1'), '2 < 3 > 1');
    },
  );
  test(
    'paragraphs keep boundaries and invisible or executable text is removed',
    () {
      expect(displayText('<p>第一段<br>第二行</p><p>第二段</p>'), '第一段 第二行 第二段');
      expect(
        displayText('<script>alert(1)</script><style>x{}</style><b>影片</b>'),
        '影片',
      );
      expect(displayText('侠\u200B探\u0000杰克'), '侠探杰克');
      expect(displayText('<em>未闭合标签'), '未闭合标签');
    },
  );
  test('CMS normalizes display fields without changing IDs or media URLs', () {
    final http = MediaHttpClient(allowPrivateNetworks: true);
    addTearDown(http.close);
    final provider = CmsProvider(
      VideoSource(
        id: 'test',
        name: '测试',
        endpoint: Uri.parse('https://example.org/api'),
      ),
      DocumentClient(http),
    );
    final item = provider.parse({
      'vod_id': 'id&amp;raw',
      'vod_name': '<em>侠</em><em>探</em>杰克',
      'vod_remarks': '&lt;b&gt;更新至8集&lt;/b&gt;',
      'vod_actor': '<a>主演</a>',
      'vod_play_from': '<b>线路</b>',
      'vod_play_url': r'<em>第一集</em>$https://example.org/a.m3u8?token=a&b=c',
    });
    expect(item.id, 'id&amp;raw');
    expect(item.title, '侠探杰克');
    expect(item.remarks, '更新至8集');
    expect(item.actors, '主演');
    expect(item.lines.single.name, '线路');
    expect(item.lines.single.episodes.single.label, '第一集');
    expect(
      item.lines.single.episodes.single.uri.toString(),
      'https://example.org/a.m3u8?token=a&b=c',
    );
  });
}
