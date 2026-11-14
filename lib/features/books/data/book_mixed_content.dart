import 'package:html/dom.dart' as dom;

import '../domain/book.dart';
import 'book_html.dart';

sealed class BookChapterSegment {
  const BookChapterSegment();
}

final class BookTextSegment extends BookChapterSegment {
  const BookTextSegment(this.text);
  final String text;
}

final class BookImageSegment extends BookChapterSegment {
  const BookImageSegment(this.address);
  final Uri address;
}

/// Extracts static HTML text and images in DOM order. Script output is outside
/// this parser; every media address still passes the source host policy.
List<BookChapterSegment> extractBookChapterSegments(
  BookSource source,
  Uri base,
  String html,
  String rule,
) {
  final selector = rule
      .replaceFirst(RegExp(r'^@css:'), '')
      .replaceFirst(RegExp(r'@(text|ownText|html)$'), '');
  final document = parseBookHtml(html);
  final parts = <BookChapterSegment>[];
  final pending = StringBuffer();
  var textSize = 0, imageCount = 0;

  void flush() {
    final text = pending
        .toString()
        .replaceAll('\r', '')
        .replaceAll(
          RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]'),
          '',
        )
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n\n');
    pending.clear();
    if (text.isNotEmpty) parts.add(BookTextSegment(text));
  }

  void append(dom.Node node, int depth) {
    if (depth > 80) return;
    if (node is dom.Text) {
      if (textSize >= 250000) return;
      final remaining = 250000 - textSize;
      final value = node.data;
      final length = value.length.clamp(0, remaining);
      pending.write(value.substring(0, length));
      textSize += length;
      return;
    }
    if (node is! dom.Element) return;
    if (node.localName == 'img') {
      if (imageCount >= 100) return;
      final address =
          node.attributes['data-src'] ??
          node.attributes['data-lazy-src'] ??
          node.attributes['data-echo'] ??
          node.attributes['data-original'] ??
          node.attributes['src'];
      if (address != null && address.isNotEmpty) {
        try {
          final uri = source.resolve(base, address, media: true);
          flush();
          parts.add(BookImageSegment(uri));
          imageCount++;
        } on FormatException {
          // An undeclared host cannot be introduced by authored HTML.
        }
      }
      return;
    }
    final block = const {
      'p',
      'div',
      'section',
      'article',
      'li',
      'blockquote',
      'br',
      'h1',
      'h2',
      'h3',
      'pre',
    }.contains(node.localName);
    if (block && pending.isNotEmpty) pending.write('\n');
    for (final child in node.nodes) {
      append(child, depth + 1);
    }
    if (block && pending.isNotEmpty) pending.write('\n');
  }

  for (final root in bookElements(document, selector)) {
    append(root, 0);
  }
  flush();
  return parts;
}
