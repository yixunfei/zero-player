import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/cms_document_parser.dart';
import 'package:zero_player/features/catalog/data/cms_provider.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import '../../test_support/http_test_server.dart';

const _xml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss><class><ty id="1">电影</ty></class><list page="1" pagecount="3">
<video><id>42</id><name><![CDATA[影片 & 标题]]></name><pic>/poster.jpg</pic>
<type>电影</type><year>2026</year><note>正片</note><des>介绍</des>
<dl><dd flag="hls"><![CDATA[第1集\$https://media.test/1.m3u8#第2集\$https://media.test/2.m3u8]]></dd>
<dd flag="mp4"><![CDATA[正片\$https://media.test/movie.mp4]]></dd></dl></video>
</list></rss>''';

void main() {
  test(
    'XML lists, details, pagination and alternatives use the CMS provider',
    () async {
      final server = await HttpTestServer.start(
        (request) => request.response.write(_xml),
      );
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(server.close);
      addTearDown(http.close);
      final provider = CmsProvider(
        VideoSource(id: 'xml', name: 'XML', endpoint: server.baseUri),
        DocumentClient(http),
      );
      final browse = await provider.browse();
      expect(browse.categories['1'], '电影');
      final detail = await provider.detail('42');
      expect(detail.title, '影片 & 标题');
      expect(detail.lines, hasLength(2));
      expect(detail.lines.first.episodes, hasLength(2));
      expect(detail.lines.first.episodes.first.uri.path, '/1.m3u8');
      expect(detail.poster, server.baseUri.resolve('poster.jpg').toString());
      expect((await provider.search('片')).pageCount, 3);
    },
  );
  test('non-catalog XML and entity declarations cannot pass probing', () {
    expect(
      () => decodeCmsDocument('<html><body>error</body></html>'),
      throwsFormatException,
    );
    expect(() => decodeCmsDocument('<rss/>'), throwsFormatException);
    expect(
      () => decodeCmsDocument('<!DOCTYPE rss><rss><list/></rss>'),
      throwsFormatException,
    );
    expect(
      decodeCmsDocument('<rss><list pagecount="0"/></rss>')['list'],
      isEmpty,
    );
  });
}
