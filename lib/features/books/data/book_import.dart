import 'dart:convert';

import '../domain/book.dart';

({List<BookSource> sources, int rejected, int duplicates}) parseBookSources(
  String input,
) {
  if (input.length > 8 * 1024 * 1024) throw const FormatException('来源文件超过大小限制');
  final raw = jsonDecode(input);
  final records = raw is List ? raw : [raw];
  if (records.length > 3000) throw const FormatException('来源数量超过限制');
  final sources = <String, BookSource>{};
  var rejected = 0;
  var duplicates = 0;
  for (final record in records) {
    try {
      if (record is! Map) throw const FormatException('无效记录');
      final converted = record.containsKey('bookSourceUrl')
          ? _legadoBook(record)
          : record.containsKey('sourceUrl')
          ? _legadoFeed(record)
          : record;
      final source = BookSource.fromJson(converted);
      if (sources.containsKey(source.id)) {
        duplicates++;
      } else {
        sources[source.id] = source;
      }
    } catch (_) {
      rejected++;
    }
  }
  return (
    sources: sources.values.toList(),
    rejected: rejected,
    duplicates: duplicates,
  );
}

Map _legadoFeed(Map raw) {
  if (raw['enableJs'] == true ||
      [
        'loginUrl',
        'loginUi',
        'jsLib',
        'ruleArticles',
        'ruleContent',
        'header',
      ].any((key) => raw[key] != null && raw[key] != '')) {
    throw const FormatException('仅支持标准 RSS/Atom 地址');
  }
  return {
    'name': raw['sourceName'],
    'url': raw['sourceUrl'],
    'kind': 'text',
    'format': 'feed',
    'group': raw['sourceGroup'],
  };
}

Map _legadoBook(Map raw) {
  final kind = switch (raw['bookSourceType'] ?? 0) {
    0 => 'text',
    1 => 'audio',
    _ => throw const FormatException('仅支持文字书及有声书'),
  };
  if ([
    'loginUrl',
    'loginUi',
    'jsLib',
    'header',
    'loginCheckJs',
  ].any((key) => raw[key] != null && raw[key] != '')) {
    throw const FormatException('来源依赖登录、请求头或脚本');
  }
  final search = raw['ruleSearch'] as Map;
  final toc = raw['ruleToc'] as Map;
  final content = raw['ruleContent'] as Map;
  final info = raw['ruleBookInfo'] is Map
      ? raw['ruleBookInfo'] as Map
      : const {};
  final searchUrl = raw['searchUrl'] as String;
  if (searchUrl.contains(',') || searchUrl.contains('<')) {
    throw const FormatException('仅支持静态 GET 搜索');
  }
  return {
    'name': raw['bookSourceName'],
    'url': raw['bookSourceUrl'],
    'kind': kind,
    'format': 'html',
    'group': raw['bookSourceGroup'],
    'search': searchUrl
        .replaceAll('{{key}}', '{key}')
        .replaceAll('{{page}}', '1'),
    'rules': {
      'list': _selector(search['bookList']),
      'title': _selector(search['name']),
      'author': _selector(search['author']),
      'book': _selector(search['bookUrl']),
      'description': _selector(search['intro']),
      'toc': _selector(info['tocUrl']),
      'chapters': _selector(toc['chapterList']),
      'chapterTitle': _selector(toc['chapterName']),
      'chapterUrl': _selector(toc['chapterUrl']),
      'nextToc': _selector(toc['nextTocUrl']),
      'content': _selector(content['content']),
      'nextContent': _selector(content['nextContentUrl']),
    },
  };
}

String _selector(Object? value) {
  if (value == null || value == '') return '';
  final original = value as String;
  if (RegExp(
    r'@js\b|<|\{\{|\}\}|&&|\|\||javascript:',
    caseSensitive: false,
  ).hasMatch(original)) {
    throw const FormatException('来源使用不受支持的动态规则');
  }
  if (original == 'text.下一页@href') return '@next';
  final raw = original
      .split('##')
      .first
      .replaceFirst(RegExp(r'^@css:', caseSensitive: false), '');
  if (const {'text', 'html', 'textNodes'}.contains(raw)) return '@text';
  if (const {'href', 'src'}.contains(raw)) return '@$raw';
  final parts = raw.split('@');
  final field =
      const {'text', 'html', 'textNodes', 'href', 'src'}.contains(parts.last)
      ? parts.removeLast()
      : null;
  final selector = parts
      .map((part) {
        final legacy = RegExp(
          r'^(class|id|tag)\.([\w-]+)(?:\.(\d+))?$',
        ).firstMatch(part);
        if (legacy == null) return part;
        final prefix = switch (legacy[1]) {
          'class' => '.',
          'id' => '#',
          _ => '',
        };
        final index = legacy[3] == null
            ? ''
            : ':nth-of-type(${int.parse(legacy[3]!) + 1})';
        return '$prefix${legacy[2]}$index';
      })
      .join(' ');
  return field == null
      ? selector
      : '$selector@${const {'href', 'src'}.contains(field) ? field : 'text'}';
}
