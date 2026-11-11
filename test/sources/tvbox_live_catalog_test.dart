import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/features/sources/data/catalog_document.dart';
import 'package:zero_player/features/sources/data/catalog_parser.dart';
import 'package:zero_player/features/sources/data/catalog_url.dart';

void main() {
  final base = Uri.parse('https://config.test/final/config.json');
  const parser = JsonSourceCatalogParser();

  test('TVBox URLs normalize Chinese hosts and a single scheme slash', () {
    expect(
      parseCatalogUrl('http://www.饭太硬.net/tv').host,
      'www.xn--sss604efuw.net',
    );
    expect(
      parseCatalogUrl('https:/config.test/短剧.json').toString(),
      'https://config.test/%E7%9F%AD%E5%89%A7.json',
    );
    expect(
      () => parseCatalogUrl('https://a:b@config.test'),
      throwsFormatException,
    );
  });

  test('recovers live and store arrays independently of broken sites', () {
    final direct = base64.encode(utf8.encode('https://live.test/a.txt'));
    final local = base64.encode(utf8.encode('http://127.0.0.1/a.txt'));
    final catalog = parser.parse('''
    {
      "storeHouse": [{"sourceName":"备份","sourceUrl":"./back.json"}],
      "sites": [{"key":invalid,"nested":{"lives":[{"url":"./trap"}]}}],
      ## TVBox comment
      "lives": [
        {"name":"直播","type":"0","url":"./playlist.txt","ua":"Custom",
         "epg":"https://guide.test/?ch={name}&date={date}"},
        {"group":"redirect","channels":[{"name":"旧版","urls":[
          "proxy://do=live&type=txt&ext=$direct",
          "proxy://do=live&type=txt&ext=$local",
          "proxy://do=spider&type=txt&ext=$direct"
        ]}]},
        {"name":"脚本","type":3,"url":"https://live.test/spider.txt"},
        {"name":"回环代理","url":"http://127.0.0.1:9978/proxy?do=live"},
      ],
    }<footer></footer>
    ''', base);
    expect(catalog.sources, isEmpty);
    expect(catalog.references.single.uri, base.resolve('back.json'));
    expect(catalog.lives.map((e) => e.url.toString()), [
      'https://config.test/final/playlist.txt',
      'https://live.test/a.txt',
    ]);
    expect(catalog.lives.first.headers, {'User-Agent': 'Custom'});
    expect(catalog.lives.first.epg, isNull);
    expect(catalog.diagnostics, hasLength(5));
  });

  test(
    'image-wrapped and self-contained encrypted configs decode as data',
    () async {
      const text = '{"lives":[{"name":"频道","url":"./tv.txt"}]}';
      final bytes = utf8.encode(text);
      final wrapped = Document(base, [
        0xff,
        0xd8,
        0xff,
        0xd9,
        ...ascii.encode('Abcd0123**${base64.encode(bytes)}'),
      ], contentType: 'image/jpeg');
      expect(await decodeCatalogDocument(wrapped), text);
      const key = 'test';
      const iv = '0123456789012';
      final box = await AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
          .encrypt(
            bytes,
            secretKey: SecretKey(ascii.encode(key.padRight(16, '0'))),
            nonce: ascii.encode(iv.padRight(16, '0')),
          );
      String hex(List<int> values) =>
          values.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      final envelope = hex([
        ...ascii.encode(r'$#test#$'),
        ...box.cipherText,
        ...ascii.encode(iv),
      ]);
      expect(
        await decodeCatalogDocument(Document(base, ascii.encode(envelope))),
        text,
      );
      await expectLater(
        decodeCatalogDocument(Document(base, ascii.encode('242300'))),
        throwsFormatException,
      );
    },
  );
}
