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

String plainBookText(dom.Node node, {int limit = 250000, bool own = false}) {
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

  if (own) {
    for (final child in node.nodes) {
      if (child is dom.Text ||
          (child is dom.Element && child.localName == 'br')) {
        append(child, 0);
      }
    }
  } else {
    append(node, 0);
  }
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

Iterable<dom.Element> bookElements(dom.Node node, String rule) {
  for (final alternative in rule.split('||')) {
    final elements = <dom.Element>{
      for (final selector in alternative.split('&&'))
        ..._select(node, selector).whereType<dom.Element>(),
    };
    if (elements.isNotEmpty) return elements;
  }
  return const [];
}

/// Static selectors with Legado's fallback and combined results.
String bookField(dom.Node node, String rule, {bool long = false}) {
  if (rule.isEmpty) return '';
  for (final alternative in rule.split('||')) {
    final values = [
      for (final part in alternative.split('&&'))
        _field(node, part.trim(), long: long),
    ].where((value) => value.isNotEmpty);
    if (values.isNotEmpty) return values.join(long ? '\n\n' : '\n');
  }
  return '';
}

Iterable<dom.Node> _select(dom.Node node, String rule) {
  if (rule.isEmpty) return [node];
  final steps = rule.split('@');
  if (steps.length > 8) throw const FormatException('选择器层数超过限制');
  Iterable<dom.Node> selected = [node];
  for (final selector in steps) {
    selected = selected
        .expand((parent) => _selectStep(parent, selector))
        .take(5000);
  }
  return selected;
}

Iterable<dom.Element> _selectStep(dom.Node node, String rule) {
  final index = RegExp(r':eq\((-?\d+)\)$').firstMatch(rule);
  final selector = index == null ? rule : rule.substring(0, index.start);
  final contains = RegExp(r':contains\(([^()]+)\)$').firstMatch(selector);
  final css = contains == null
      ? selector
      : selector.substring(0, contains.start);
  if (css.isEmpty) return const [];
  final elements = switch (node) {
    dom.Document doc => doc.querySelectorAll(css),
    dom.Element element => element.querySelectorAll(css),
    _ => const <dom.Element>[],
  };
  final filtered = contains == null
      ? elements
      : elements
            .where((element) => element.text.contains(contains[1]!))
            .toList();
  if (index == null) return filtered;
  final offset = int.tryParse(index[1]!);
  if (offset == null) return const [];
  final position = offset < 0 ? filtered.length + offset : offset;
  return position >= 0 && position < filtered.length
      ? [filtered[position]]
      : const [];
}

String _field(dom.Node node, String rule, {required bool long}) {
  const operations = {
    'text',
    'ownText',
    'href',
    'src',
    'alt',
    'title',
    'value',
    'content',
    'filename',
    'next',
  };
  final separator = rule.lastIndexOf('@');
  final suffix = separator == -1 ? '' : rule.substring(separator + 1);
  final explicit = operations.contains(suffix);
  final selector = explicit ? rule.substring(0, separator) : rule;
  final field = explicit ? suffix : 'text';
  if (field == 'next') {
    return bookElements(node, 'a[href]')
            .take(5000)
            .where((a) => RegExp(r'^\s*下一页\s*[>»›]?\s*$').hasMatch(a.text))
            .firstOrNull
            ?.attributes['href'] ??
        '';
  }
  final selected = _select(node, selector);
  if (!long) {
    return selected
            .map((item) => _value(item, field, false))
            .where((value) => value.isNotEmpty)
            .firstOrNull ??
        '';
  }
  final buffer = StringBuffer();
  for (final item in selected.take(4000)) {
    final value = _value(item, field, true);
    if (value.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.write('\n\n');
    final remaining = 250000 - buffer.length;
    if (remaining <= 0) break;
    buffer.write(
      value.length > remaining ? value.substring(0, remaining) : value,
    );
  }
  return buffer.toString();
}

String _value(dom.Node node, String field, bool long) {
  return switch (field) {
    'text' => long ? plainBookText(node) : (node.text ?? '').trim(),
    'ownText' =>
      long
          ? plainBookText(node, own: true)
          : node.nodes
                .whereType<dom.Text>()
                .map((text) => text.data.trim())
                .where((value) => value.isNotEmpty)
                .join(' '),
    'filename' =>
      Uri.tryParse(node.attributes['href'] ?? '')?.pathSegments.lastOrNull ??
          '',
    _ => node.attributes[field] ?? '',
  };
}
