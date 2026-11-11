import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

dom.Document parseBookHtml(String input) {
  final document = html.parse(input);
  for (final node in document.querySelectorAll(
    'script, style, iframe, object, embed, template, noscript, svg, form, nav, '
    '[hidden], [aria-hidden="true"]',
  )) {
    node.remove();
  }
  return document;
}

String plainBookText(dom.Node node, {int limit = 250000}) {
  final buffer = StringBuffer();
  void append(dom.Node current, int depth) {
    if (depth > 80 || buffer.length >= limit) return;
    if (current is dom.Text) {
      final value = current.data;
      buffer.write(
        value.substring(0, value.length.clamp(0, limit - buffer.length)),
      );
      return;
    }
    final block =
        current is dom.Element &&
        const {
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
        }.contains(current.localName);
    if (block && buffer.isNotEmpty) buffer.write('\n');
    for (final child in current.nodes) {
      append(child, depth + 1);
    }
    if (block && buffer.isNotEmpty) buffer.write('\n');
  }

  append(node, 0);
  return buffer
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
}

/// A static CSS selector followed by a fixed extraction operation.
String bookField(dom.Node node, String rule, {bool long = false}) {
  if (rule.isEmpty) return '';
  final parts = rule.split('@');
  if (parts.length > 2) throw const FormatException('不支持的字段选择器');
  final selected = parts.first.isEmpty
      ? node
      : switch (node) {
          dom.Document doc => doc.querySelector(parts.first),
          dom.Element element => element.querySelector(parts.first),
          _ => null,
        };
  if (selected == null) return '';
  final field = parts.length == 2 ? parts.last : 'text';
  return switch (field) {
    'text' => long ? plainBookText(selected) : (selected.text ?? '').trim(),
    'href' ||
    'src' => selected is dom.Element ? selected.attributes[field] ?? '' : '',
    'filename' =>
      selected is dom.Element
          ? Uri.tryParse(
                  selected.attributes['href'] ?? '',
                )?.pathSegments.lastOrNull ??
                ''
          : '',
    'next' =>
      (node is dom.Document ? node : throw const FormatException('分页规则必须用于文档'))
              .querySelectorAll('a[href]')
              .take(5000)
              .where((a) => RegExp(r'^\s*下一页\s*[>»›]?\s*$').hasMatch(a.text))
              .firstOrNull
              ?.attributes['href'] ??
          '',
    _ => throw const FormatException('不支持的字段提取方式'),
  };
}
