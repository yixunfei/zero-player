import 'dart:convert';

import '../../domain/book.dart';
import 'legado_discovery.dart';
import 'legado_request.dart';

BookSource importLegadoBook(Map raw) {
  final kind = switch ('${raw['bookSourceType'] ?? 0}'.toLowerCase()) {
    '0' || '' || 'text' => 'text',
    '1' || 'audio' => 'audio',
    _ => throw const FormatException('仅支持文字书和有声书'),
  };
  final searchRule = raw.containsKey('searchUrl')
      ? _text(raw['searchUrl'])
      : _oldUrl(_text(raw['ruleSearchUrl']));
  final search = const {'#', 'about:blank'}.contains(searchRule.toLowerCase())
      ? ''
      : searchRule;
  final explore = legadoCategories(
    raw['exploreUrl'] ?? _oldUrl(_text(raw['ruleFindUrl']), discovery: true),
  );
  final bookUrlPattern = _text(raw['bookUrlPattern']);
  if (search.isEmpty && explore.isEmpty && bookUrlPattern.isEmpty) {
    throw const FormatException('缺少 Legado 搜索或发现入口');
  }
  final key = legadoAddressPart(_text(raw['bookSourceUrl']));
  final declared = _declaredEndpoint(key);
  final endpoint = declared == null
      ? Uri.parse('${_endpoint(search).origin}/')
      : legacyBookUri(declared);
  final modern = _modernBookRules(raw)..removeWhere((_, rule) => rule.isEmpty);
  final rules = _oldBookRules(raw)
    ..removeWhere((_, rule) => rule.isEmpty)
    ..addAll(modern);
  if (rules['content']?.isNotEmpty != true &&
      (kind == 'text' || rules['chapters']?.isNotEmpty != true)) {
    throw const FormatException('缺少 Legado 正文或音频规则');
  }
  final source = BookSource.fromJson({
    'name': raw['bookSourceName'],
    'url': '$endpoint',
    'kind': kind,
    'format': 'html',
    'group': raw['bookSourceGroup'],
    'sample': _map(raw['ruleSearch'])['checkKeyWord'],
    'mediaHosts': raw['mediaHosts'],
    'sourceKey': _sourceKey(key, declared, endpoint),
    'updatedAt': int.tryParse('${raw['lastUpdateTime']}') ?? 0,
    'legado': {
      'search': search,
      'explore': explore.map((category) => category.toJson()).toList(),
      'enabledExplore': raw['enabledExplore'] != false,
      'bookUrlPattern': bookUrlPattern,
      'rules': rules,
      'headers': legadoHeaders(raw['header'], endpoint),
      'library': raw['jsLib'],
      'comment': _text(raw['bookSourceComment']),
    },
  });
  final literal = legadoAddressPart(search);
  if (literal.startsWith('https://') || literal.startsWith('http://')) {
    source.resolve(
      endpoint,
      literal.replaceAll(RegExp(r'\{\{.*?\}\}'), 'test'),
    );
  }
  return source;
}

BookSource importLegadoFeed(Map raw) {
  if (const {'1', '2'}.contains('${raw['type']}')) {
    throw const FormatException('仅支持文字书和有声书');
  }
  final address = _text(raw['sourceUrl']);
  final endpoint = _endpoint(address);
  final articles = _text(raw['ruleArticles']);
  final content = _map(raw['ruleContent']);
  final kind = switch ('${raw['bookSourceType'] ?? raw['kind'] ?? ''}'
      .toLowerCase()) {
    '1' || 'audio' => 'audio',
    _ => 'text',
  };
  return BookSource.fromJson({
    'name': raw['sourceName'],
    'url': '$endpoint',
    'kind': kind,
    'format': 'feed',
    'group': raw['sourceGroup'],
    'mediaHosts': raw['mediaHosts'],
    'legado': {
      'search': address,
      'explore': legadoCategories(
        raw['sortUrl'],
      ).map((category) => category.toJson()).toList(),
      'headers': legadoHeaders(raw['header'], endpoint),
      'library': raw['jsLib'],
      'rules': {
        'articles': articles,
        'articleTitle': _text(raw['ruleTitle']),
        'articleLink': _text(raw['ruleLink']),
        'articleDescription': _text(raw['ruleDescription']),
        'nextArticles': _text(raw['ruleNextPage']),
        'content': content.isEmpty
            ? _text(raw['ruleContent'])
            : _text(content['content']),
        'nextContent': _text(
          raw['nextContentUrl'] ?? content['nextContentUrl'],
        ),
        'replaceContent': _text(content['replaceRegex']),
      },
    },
  });
}

Map<String, String> _modernBookRules(Map raw) {
  final search = _map(raw['ruleSearch']);
  final explore = _map(raw['ruleExplore']);
  final info = _map(raw['ruleBookInfo']);
  final toc = _map(raw['ruleToc']);
  final content = _map(raw['ruleContent']);
  return {
    ..._listRules('search', search),
    ..._listRules('explore', explore),
    'infoInit': _text(info['init']),
    'infoTitle': _text(info['name']),
    'infoAuthor': _text(info['author']),
    'infoDescription': _text(info['intro']),
    'infoCover': _text(info['coverUrl']),
    'infoCategory': _text(info['kind']),
    'infoWordCount': _text(info['wordCount']),
    'infoLatest': _text(info['lastChapter']),
    'infoUpdated': _text(info['updateTime']),
    'toc': _text(info['tocUrl']),
    'chapters': _text(toc['chapterList'] ?? toc['list']),
    'chapterTitle': _text(toc['chapterName']),
    'chapterUrl': _text(toc['chapterUrl']),
    'chapterVolume': _text(toc['isVolume']),
    'nextToc': _text(toc['nextTocUrl']),
    'content': _text(content['content']),
    'nextContent': _text(content['nextContentUrl']),
    'replaceContent': _text(content['replaceRegex']),
  };
}

Map<String, String> _listRules(String prefix, Map group) => {
  '${prefix}List': _text(group['bookList']),
  '${prefix}Title': _text(group['name']),
  '${prefix}Link': _text(group['bookUrl']),
  '${prefix}Author': _text(group['author']),
  '${prefix}Cover': _text(group['coverUrl']),
  '${prefix}Category': _text(group['kind']),
  '${prefix}Description': _text(group['intro']),
  '${prefix}WordCount': _text(group['wordCount']),
  '${prefix}Latest': _text(group['lastChapter']),
  '${prefix}Updated': _text(group['updateTime']),
};

Map<String, String> _oldBookRules(Map raw) => {
  for (final entry in const {
    'searchList': 'ruleSearchList',
    'searchTitle': 'ruleSearchName',
    'searchLink': 'ruleSearchNoteUrl',
    'searchAuthor': 'ruleSearchAuthor',
    'searchDescription': 'ruleSearchIntroduce',
    'searchCover': 'ruleSearchCoverUrl',
    'searchCategory': 'ruleSearchKind',
    'infoTitle': 'ruleBookName',
    'infoAuthor': 'ruleBookAuthor',
    'infoDescription': 'ruleIntroduce',
    'infoCover': 'ruleCoverUrl',
    'infoCategory': 'ruleBookKind',
    'toc': 'ruleChapterUrl',
    'chapters': 'ruleChapterList',
    'chapterTitle': 'ruleChapterName',
    'chapterUrl': 'ruleContentUrl',
    'nextToc': 'ruleChapterUrlNext',
    'content': 'ruleBookContent',
    'nextContent': 'ruleContentUrlNext',
  }.entries)
    entry.key: _oldRule(_text(raw[entry.value])),
};

Map _map(Object? raw) {
  if (raw is Map) return raw;
  if (raw is String &&
      raw.trimLeft().startsWith('{') &&
      !raw.trimLeft().startsWith('{{')) {
    try {
      final parsed = decodeLegadoJson(raw);
      if (parsed is Map) return parsed;
    } on FormatException {
      return const {};
    }
  }
  return const {};
}

String _text(Object? raw) => raw is String ? raw.trim() : '';

Uri? _declaredEndpoint(String value) {
  if (value.contains('://')) return Uri.parse(value);
  if (RegExp(
    r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:[/?#]|$)',
    caseSensitive: false,
  ).hasMatch(value)) {
    return Uri.tryParse('https://$value');
  }
  return null;
}

Uri _endpoint(Object? raw) {
  final value = legadoAddressPart(_text(raw));
  final uri = _declaredEndpoint(
    value.replaceAll(RegExp(r'\{\{.*?\}\}'), 'test'),
  );
  if (uri != null) return legacyBookUri(uri);
  throw const FormatException('缺少可验证的公网 HTTPS 来源地址');
}

String _sourceKey(String raw, Uri? declared, Uri endpoint) {
  if (declared == null) return 'alias:${endpoint.host}:$raw';
  final path = endpoint.path == '/' ? '' : endpoint.path;
  final query = endpoint.hasQuery ? '?${endpoint.query}' : '';
  final fragment = declared.hasFragment ? '#${declared.fragment}' : '';
  if (path.isEmpty && query.isEmpty && fragment.isEmpty) return '';
  return '${endpoint.host.replaceFirst(RegExp(r'^www\.'), '')}$path$query$fragment';
}

String _oldUrl(String value, {bool discovery = false}) {
  var url = value
      .replaceAll('{,_searchPage}', '<,{{page}}>')
      .replaceAll('_searchPage', '{{page}}')
      .replaceAll(RegExp(r'\bsearchKey\b(?!\s*=)'), '{{key}}');
  if (discovery) return url;
  final post = RegExp(r'@([\w.-]+=[\s\S]*)$').firstMatch(url);
  if (post != null) {
    final body = post[1]!;
    url =
        '${url.substring(0, post.start)},${jsonEncode({'method': 'POST', 'body': body})}';
  }
  return url;
}

String _oldRule(String value) {
  final match = RegExp(
    r'^(.*?@\w+|\w+)#([^#].*)$',
    dotAll: true,
  ).firstMatch(value);
  return match == null
      ? value
      : '${match[1]}##${match[2]!.replaceFirst('#', '##')}';
}
