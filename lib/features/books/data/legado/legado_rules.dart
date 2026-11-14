import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:json_path/json_path.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../../domain/book.dart';
import '../book_html.dart';
import 'legado_css.dart';
import 'legado_rule_tokens.dart';
import 'legado_script.dart';

final class LegadoRules {
  LegadoRules(
    this.source,
    this.uri,
    this.input, {
    this.key = '',
    this.page = 1,
    this.book,
    this.chapter,
    this.documents = const {},
  });

  final BookSource source;
  final Uri uri;
  final String input, key;
  final int page;
  final Book? book;
  final BookChapter? chapter;
  final Map<String, String> documents;
  late final Object? root = _parse(input);

  List<Object?> elements(String rule, Object? value) {
    return _evaluate(
      rule,
      value,
      list: true,
    ).where((item) => item != null).take(5000).toList();
  }

  List<Object?> rawValues(String rule, Object? value) => _evaluate(
    rule,
    value,
    list: false,
  ).where((item) => item != null).take(5000).toList();

  String field(
    String rule,
    Object? value, {
    bool long = false,
    bool single = false,
  }) {
    final items = _evaluate(
      rule,
      value,
      list: false,
    ).map((item) => _asText(item, long: long)).where((item) => item.isNotEmpty);
    if (single) return items.firstOrNull ?? '';
    final buffer = StringBuffer();
    for (final item in items.take(4000)) {
      if (buffer.isNotEmpty) buffer.write(long ? '\n\n' : '\n');
      final space = (long ? 250000 : 4096) - buffer.length;
      if (space <= 0) break;
      buffer.write(item.length > space ? item.substring(0, space) : item);
    }
    return buffer.toString();
  }

  Object? script(String code, Object? value) => runLegadoScript(
    code,
    library: source.legado!.library,
    context: {
      'result': _jsonValue(value),
      'src': input,
      'baseUrl': uri.toString(),
      'key': key,
      'page': page,
      'source': {
        'bookSourceUrl': source.endpoint.toString(),
        'sourceUrl': source.endpoint.toString(),
        'bookSourceName': source.name,
        'bookSourceGroup': source.group,
        'bookSourceComment': source.legado!.comment,
      },
      'book': {
        'name': book?.title ?? '',
        'author': book?.author ?? '',
        'bookUrl': book?.uri.toString() ?? '',
      },
      'chapter': {
        'title': chapter?.title ?? '',
        'url': chapter?.uri.toString() ?? '',
      },
    },
    documents: documents,
    select: _scriptSelect,
  );

  Object? _scriptSelect(String method, String rule, Object? value) {
    if (rule.length > 1024 ||
        legadoScriptMarker.hasMatch(rule) ||
        rule.contains('{{') ||
        rule.contains('##')) {
      throw const FormatException('脚本只可调用声明式选择器');
    }
    final target = value is String ? _parse(value) : value;
    return switch (method) {
      'string' => field(rule, target),
      'list' => _evaluate(
        rule,
        target,
        list: false,
      ).map((item) => _asText(item)).take(200).toList(),
      _ => elements(rule, target).map(_jsonValue).take(200).toList(),
    };
  }

  Iterable<Object?> _evaluate(
    String rule,
    Object? value, {
    required bool list,
    int depth = 0,
  }) {
    final text = rule.trim();
    if (text.isEmpty) return const [];
    if (depth > 8) throw const FormatException('Legado 规则层数超过限制');
    final marker = legadoScriptMarker.firstMatch(text);
    if (marker != null) return _withScript(text, marker, value, list, depth);
    final parts = splitLegadoRule(text, '##');
    final expression = parts.first;
    final selected = _select(expression, value, list: list, depth: depth);
    if (parts.length == 1 || parts[1].isEmpty) return selected;
    return selected
        .take(5000)
        .map(
          (item) => _replace(
            _asText(item),
            parts[1],
            parts.length > 2 ? parts[2] : '',
            parts.length > 3,
          ),
        );
  }

  Iterable<Object?> _withScript(
    String rule,
    RegExpMatch marker,
    Object? value,
    bool list,
    int depth,
  ) {
    final selector = rule.substring(0, marker.start).trim();
    Object? selected = value;
    if (selector.isNotEmpty) {
      final results = _evaluate(selector, value, list: list, depth: depth + 1);
      selected = list
          ? results.take(5000).toList()
          : results.map((item) => _asText(item)).join('\n');
    }
    final end = marker[0]!.startsWith('<')
        ? RegExp(
            r'</js>',
            caseSensitive: false,
          ).firstMatch(rule.substring(marker.end))
        : null;
    if (marker[0]!.startsWith('<') && end == null) {
      throw const FormatException('Legado 脚本块未闭合');
    }
    final code = rule.substring(
      marker.end,
      end == null ? rule.length : marker.end + end.start,
    );
    final result = script(code, selected);
    final rest = end == null ? '' : rule.substring(marker.end + end.end).trim();
    if (rest.isNotEmpty) {
      return _evaluate(rest, result, list: list, depth: depth + 1);
    }
    return _values(result);
  }

  Iterable<Object?> _select(
    String rule,
    Object? value, {
    required bool list,
    required int depth,
  }) {
    if (rule.isEmpty) return _values(value);
    for (final operator in const ['||', '&&', '%%']) {
      final parts = splitLegadoRule(rule, operator);
      if (parts.length <= 1) continue;
      if (parts.length > 32) throw const FormatException('Legado 组合规则过多');
      return _combined(parts, operator, value, list, depth);
    }
    if (rule.contains('{{') || rule.contains(r'{$')) {
      return [_template(rule, value, depth)];
    }
    final lower = rule.toLowerCase();
    if (lower.startsWith('https://') || lower.startsWith('http://')) {
      return [rule];
    }
    if (lower.startsWith('@json:') ||
        value is Map ||
        value is List ||
        rule.startsWith(r'$.') ||
        rule.startsWith(r'$[')) {
      return _json(rule, value);
    }
    if (lower.startsWith('@xpath:') ||
        rule.startsWith('/') ||
        rule.startsWith('./')) {
      final xpath = rule.replaceFirst(
        RegExp(r'^@xpath:', caseSensitive: false),
        '',
      );
      if (lower.startsWith('@xpath:') ||
          rule.startsWith('//') ||
          rule.startsWith('.//') ||
          rule.startsWith('/html/') ||
          rule.startsWith('./')) {
        return _xpath(xpath, value);
      }
      return [rule];
    }
    if (rule.startsWith(':')) {
      return _regex(
        rule.substring(1),
      ).allMatches(_asText(value)).take(5000).map((match) => match[0]);
    }
    final node = value is dom.Node ? value : parseBookHtml(_asText(value));
    final selector = rule.replaceFirst(
      RegExp(r'^(?:@css:|@@)', caseSensitive: false),
      '',
    );
    return selectLegadoCss(node, selector, list: list);
  }

  Iterable<Object?> _combined(
    List<String> parts,
    String operator,
    Object? value,
    bool list,
    int depth,
  ) sync* {
    final groups = <List<Object?>>[];
    for (final part in parts) {
      final results = _evaluate(part, value, list: list, depth: depth + 1)
          .where(
            (item) =>
                item != null && (item is! String || item.trim().isNotEmpty),
          )
          .take(5000)
          .toList();
      if (results.isEmpty) continue;
      if (operator == '||') {
        yield* results;
        return;
      }
      groups.add(results);
    }
    if (operator == '%%') {
      for (var i = 0; groups.any((group) => i < group.length); i++) {
        for (final group in groups) {
          if (i < group.length) yield group[i];
        }
      }
    } else {
      yield* groups.expand((group) => group);
    }
  }

  String _template(String rule, Object? value, int depth) => rule
      .replaceAllMapped(RegExp(r'\{\{(.*?)\}\}|\{(\$[^{}]+)\}', dotAll: true), (
        match,
      ) {
        final field = (match[1] ?? match[2]!).trim();
        if (field == 'baseUrl') return uri.toString();
        final results = _evaluate(field, value, list: false, depth: depth + 1);
        return results.map((item) => _asText(item)).firstOrNull ?? '';
      });
}

Object? _parse(String input) {
  final value = input.trimLeft();
  if (value.startsWith('{') || value.startsWith('[')) {
    try {
      return jsonDecode(value);
    } on FormatException {
      // HTML responses sometimes begin with a literal bracket.
    }
  }
  return parseBookHtml(input);
}

Iterable<Object?> _json(String rule, Object? value) {
  var path = rule
      .replaceFirst(RegExp(r'^@json:', caseSensitive: false), '')
      .trim();
  if (!path.startsWith(r'$')) {
    path = path.startsWith('[') ? '\$$path' : '\$.$path';
  }
  path = path.replaceAll('.[', '[');
  final target = value is String ? _parse(value) : value;
  if (target is dom.Node) return const [];
  return JsonPath(
    path,
  ).read(target).take(5000).expand((match) => _values(match.value));
}

Iterable<Object?> _xpath(String rule, Object? value) {
  final node = value is dom.Node ? value : parseBookHtml(_asText(value));
  final root = node is dom.Document ? node.documentElement : node;
  if (root == null) return const [];
  final result = HtmlXPath.node(
    root,
  ).query(rule.startsWith('.//') ? rule.substring(1) : rule);
  if (result.attrs.any((attribute) => attribute != null)) return result.attrs;
  return result.nodes.map((node) => node.node);
}

Iterable<Object?> _values(Object? value) => value is List ? value : [value];

Object? _jsonValue(Object? value) => switch (value) {
  dom.Document node => node.outerHtml,
  dom.Element node => node.outerHtml,
  dom.Node node => node.text,
  List values => values.map(_jsonValue).toList(),
  _ => value,
};

String _asText(Object? value, {bool long = false}) {
  if (value == null) return '';
  if (value is dom.Node) {
    return long ? plainBookText(value) : (value.text ?? '').trim();
  }
  final text = value is String ? value : '$value';
  if (!long) return text.trim();
  return RegExp(r'<[/!]?[A-Za-z]').hasMatch(text)
      ? plainBookText(parseBookHtml(text))
      : plainBookText(dom.Text(text));
}

String cleanLegadoContent(String input, String rule) {
  if (rule.isEmpty) return input;
  final segments = splitLegadoRule(
    rule,
    '##',
  ).where((part) => part.isNotEmpty).toList();
  if (segments.isEmpty) return input;
  return plainBookText(
    dom.Text(
      _replace(
        input,
        segments[0],
        segments.length > 1 ? segments[1] : '',
        false,
      ),
    ),
  );
}

RegExp _regex(String expression) {
  final flags = RegExp(r'^\(\?([ims]+)\)').firstMatch(expression);
  final enabled = flags?[1] ?? '';
  return RegExp(
    flags == null ? expression : expression.substring(flags.end),
    caseSensitive: !enabled.contains('i'),
    multiLine: enabled.contains('m'),
    dotAll: enabled.contains('s'),
  );
}

String _replace(
  String text,
  String expression,
  String substitution,
  bool first,
) {
  final pattern = _regex(expression);
  String replacement(Match match) =>
      substitution.replaceAllMapped(RegExp(r'\$(\d{1,2})'), (group) {
        final index = int.parse(group[1]!);
        return index <= match.groupCount ? match[index] ?? '' : '';
      });
  if (first) {
    final match = pattern.firstMatch(text);
    return match == null ? '' : replacement(match);
  }
  final output = StringBuffer();
  var start = 0;
  for (final match in pattern.allMatches(text)) {
    output.write(text.substring(start, match.start));
    output.write(replacement(match));
    if (output.length > 500000) {
      throw const FormatException('Legado 替换结果超过大小限制');
    }
    start = match.end;
  }
  output.write(text.substring(start));
  if (output.length > 500000) throw const FormatException('Legado 替换结果超过大小限制');
  return output.toString();
}
