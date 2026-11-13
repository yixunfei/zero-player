import 'package:html/dom.dart' as dom;

import '../book_html.dart';
import 'legado_rule_tokens.dart';

Iterable<Object?> selectLegadoCss(
  dom.Node node,
  String rule, {
  required bool list,
}) {
  final steps = splitLegadoRule(rule, '@');
  if (steps.length > 12) throw const FormatException('Legado 选择器层数超过限制');
  final suffix = steps.last;
  final field =
      !list &&
          _isExtraction(suffix) &&
          (steps.length > 1 ||
              _directFields.contains(suffix) ||
              node.attributes.containsKey(suffix))
      ? steps.removeLast()
      : '';
  Iterable<dom.Node> result = [node];
  for (final step in steps.where((step) => step.isNotEmpty)) {
    result = result.expand((parent) => _step(parent, step)).take(5000);
  }
  if (field.isEmpty) return result;
  return result.map((node) => _extract(node, field));
}

bool _isExtraction(String suffix) =>
    RegExp(r'^[A-Za-z_][\w:-]*$').hasMatch(suffix);

const _directFields = {
  'text',
  'textNodes',
  'ownText',
  'html',
  'all',
  'href',
  'src',
  'alt',
  'title',
  'content',
  'value',
  'onclick',
};

String _extract(dom.Node node, String field) {
  return switch (field.toLowerCase()) {
    'text' => (node.text ?? '').trim(),
    'owntext' =>
      node.nodes
          .whereType<dom.Text>()
          .map((part) => part.data.trim())
          .where((text) => text.isNotEmpty)
          .join(' '),
    'textnodes' => plainBookText(node, own: true),
    'html' => node is dom.Element ? node.innerHtml : node.text ?? '',
    'all' => node is dom.Element ? node.outerHtml : node.text ?? '',
    _ => node.attributes[field] ?? '',
  };
}

Iterable<dom.Element> _step(dom.Node node, String rule) {
  final indexed = RegExp(
    r'^(.*?)(?:\[([!\d,:.\- ]+)\]|([.!])(-?\d+(?:[:.]?-?\d+)*))$',
  ).firstMatch(rule);
  final selector = indexed?[1] ?? rule;
  final base = _css(selector);
  final candidates =
      (base == 'children' || base.isEmpty
              ? node.children
              : bookElements(node, base))
          .take(5000)
          .toList();
  if (indexed == null) return candidates;
  final indices = indexed[2] ?? indexed[4]!;
  return _indexed(
    candidates,
    indices,
    exclude: indexed[3] == '!' || indices.startsWith('!'),
  );
}

String _css(String selector) {
  final value = selector.trim();
  if (value.startsWith('text.')) {
    return '*:contains(${value.substring(5)})';
  }
  if (value.startsWith('class.')) {
    final classes = value.substring(6).trim().split(RegExp(r'\s+'));
    return '.${classes.join('.')}';
  }
  return value
      .replaceFirst(RegExp(r'^id\.'), '#')
      .replaceFirst(RegExp(r'^tag\.'), '');
}

Iterable<T> _indexed<T>(
  List<T> rows,
  String expression, {
  required bool exclude,
}) {
  if (rows.isEmpty) return const [];
  final chosen = <int>{};
  int position(String value, int fallback) {
    final parsed = int.tryParse(value.trim()) ?? fallback;
    return parsed < 0 ? rows.length + parsed : parsed;
  }

  for (final range in expression.replaceFirst('!', '').split(RegExp(r'[,.]'))) {
    final bounds = range.split(':');
    if (bounds.length == 1) {
      final at = position(bounds.first, rows.length);
      if (at >= 0 && at < rows.length) chosen.add(at);
      continue;
    }
    final from = position(bounds.first, 0).clamp(0, rows.length - 1);
    final to = position(bounds[1], rows.length - 1).clamp(0, rows.length - 1);
    final stride = (int.tryParse(bounds.length > 2 ? bounds[2] : '') ?? 1)
        .abs()
        .clamp(1, rows.length);
    for (
      var at = from;
      from <= to ? at <= to : at >= to;
      at += from <= to ? stride : -stride
    ) {
      chosen.add(at);
    }
  }
  if (exclude) {
    return rows.indexed
        .where((row) => !chosen.contains(row.$1))
        .map((row) => row.$2);
  }
  return chosen.map((index) => rows[index]);
}
