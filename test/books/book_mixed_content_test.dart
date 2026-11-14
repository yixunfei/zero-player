import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/books/data/book_mixed_content.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  test('static mixed chapter keeps text and allowed images in DOM order', () {
    final source = BookSource.fromJson({
      'name': '图文样本',
      'kind': 'text',
      'format': 'html',
      'url': 'https://books.test/',
      'search': '/search/{key}',
      'mediaHosts': ['images.test'],
      'rules': {
        'list': '.book',
        'title': 'a@text',
        'book': 'a@href',
        'chapters': '.chapter',
        'chapterTitle': '@text',
        'chapterUrl': '@href',
        'content': '#content@text',
      },
    });
    final parts = extractBookChapterSegments(
      source,
      Uri.parse('https://books.test/chapter/1'),
      '''<section id="content"><p>开头。</p>
      <img data-src="https://images.test/1.jpg">
      <p>图注。</p><img src="https://bad.test/skip.jpg">
      <img src="/2.png"><p>结尾。</p><script>hidden()</script></section>''',
      '#content@text',
    );
    expect(parts.length, 5);
    expect((parts[0] as BookTextSegment).text, '开头。');
    expect(
      (parts[1] as BookImageSegment).address.toString(),
      'https://images.test/1.jpg',
    );
    expect((parts[2] as BookTextSegment).text, '图注。');
    expect(
      (parts[3] as BookImageSegment).address.toString(),
      'https://books.test/2.png',
    );
    expect((parts[4] as BookTextSegment).text, '结尾。');
    final htmlRule = extractBookChapterSegments(
      source,
      Uri.parse('https://books.test/chapter/1'),
      '<div id="content">文字<img src="/1.png">尾声</div>',
      '#content@html',
    );
    expect(htmlRule.map((part) => part.runtimeType), [
      BookTextSegment,
      BookImageSegment,
      BookTextSegment,
    ]);
  });
}
