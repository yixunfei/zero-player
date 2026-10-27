import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/sources/data/catalog_parser.dart';
import 'package:zero_player/features/sources/data/jsonc_decoder.dart';

void main() {
  final origin = Uri.parse('https://config.test/root.json');
  const parser = JsonSourceCatalogParser();

  test('JSONC preserves URL comment markers, quoted commas and escapes', () {
    expect(
      decodeJsonc(r'''{
      // Comment
      "url": "https://api.test/a/*value*/?q=,}",
      "quote": "a\"b", /* Comment */
    }'''),
      {'url': 'https://api.test/a/*value*/?q=,}', 'quote': 'a"b'},
    );
  });

  test(
    'Spider and unknown types are explicit diagnostics, never executable',
    () {
      final result = parser.parse('''{"sites":[
      {"name":"CMS","type":1,"api":"https://api.test/vod?token=1"},
      {"name":"Spider","type":3,"api":"csp_X"},
      {"name":"Remote JS","type":1,"api":"https://api.test/a.js"},
      {"name":"Unknown","api":"https://api.test/unknown"}
    ]}''', origin);
      expect(result.sources.length, 1);
      expect(result.sources.single.endpoint.query, 'token=1');
      expect(result.sources.single.requestedEnabled, isFalse);
      expect(result.diagnostics.length, 3);
    },
  );

  test(
    'multi catalog preview preserves relative URLs and rejects self loops',
    () {
      final result = parser.parse('''{"urls":[
      {"name":"one","url":"child.json"},
      {"name":"loop","url":"root.json"},
      {"name":"duplicate","url":"child.json"}
    ]}''', origin);
      expect(
        result.references.single.uri.toString(),
        'https://config.test/child.json',
      );
      expect(result.sources, isEmpty);
      expect(result.diagnostics.length, 2);
    },
  );

  test('exact duplicates merge but signed variants are retained', () {
    final result = parser.parse('''[
      {"name":"A","baseUrl":"https://api.test/vod?token=1","enabled":true},
      {"name":"B","url":"https://api.test/vod?token=1"},
      {"name":"C","url":"https://api.test/vod?token=2"}
    ]''', origin);
    expect(result.sources.length, 2);
    expect(result.sources.first.requestedEnabled, isTrue);
    expect(result.diagnostics.single.reason, '重复地址');
  });

  test('malformed, oversized and deeply nested configs fail explicitly', () {
    expect(() => parser.parse('<html/>', origin), throwsFormatException);
    expect(
      () => const JsonSourceCatalogParser(maxBytes: 2).parse('[{}]', origin),
      throwsFormatException,
    );
    expect(
      () => parser.parse('${'[' * 65}${']' * 65}', origin),
      throwsFormatException,
    );
    expect(
      () => parser.parse('{/*unterminated', origin),
      throwsFormatException,
    );
  });
}
