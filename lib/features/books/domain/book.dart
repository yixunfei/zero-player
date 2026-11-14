import 'dart:io';

import '../../../core/network/network_target_policy.dart';
import '../../sources/domain/video_source.dart';
import 'legado_source.dart';

enum BookKind { text, audio }

enum BookFormat { html, feed, featured }

String bookLabel(Object? value, [int limit = 160]) {
  final text = value is String
      ? value
            .replaceAll(
              RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'),
              ' ',
            )
            .trim()
      : '';
  return text.length <= limit ? text : text.substring(0, limit);
}

Uri publicBookUri(Uri uri, {bool legacyQueryEncoding = false}) {
  NetworkTargetPolicy.validateUri(
    uri,
    legacyQueryEncoding: legacyQueryEncoding,
  );
  final host = uri.host.toLowerCase();
  if (uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.authority.contains('@') ||
      uri.toString().length > 2048 ||
      !RegExp(
        r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]*$',
      ).hasMatch(host) ||
      InternetAddress.tryParse(host) != null ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.home.arpa')) {
    throw const FormatException('来源仅允许公网 HTTPS 域名');
  }
  return uri.removeFragment();
}

/// Old Legado exports often advertise HTTP even where the publisher offers TLS.
Uri legacyBookUri(Uri uri, {bool legacyQueryEncoding = false}) => publicBookUri(
  uri.scheme == 'http' && uri.port == 80
      ? uri.replace(scheme: 'https', port: 443)
      : uri,
  legacyQueryEncoding: legacyQueryEncoding,
);

final class BookSource {
  BookSource.fromJson(Map data, {this.builtin = false})
    : name = bookLabel(data['name']),
      group = bookLabel(data['group'], 60),
      kind = BookKind.values.byName(data['kind'] as String),
      format = BookFormat.values.byName(data['format'] as String),
      endpoint = publicBookUri(Uri.parse(data['url'] as String)),
      search = _rule(data['search'], 1024),
      searchForm = _form(data['searchForm']),
      searchCharset = data['searchCharset'] as String? ?? 'utf-8',
      discover = _rule(data['discover'], 1024),
      discoveryCategories = LegadoSource.readCategories(
        data['discoveryCategories'],
      ),
      sample = bookLabel(data['sample'], 80),
      rules = _rules(data['rules']),
      legado = data['legado'] == null
          ? null
          : LegadoSource.fromJson(data['legado'] as Map),
      mediaHosts = _hosts(data['mediaHosts']),
      originNote = bookLabel(data['originNote'], 240),
      sourceKey = _rule(data['sourceKey'], 2048),
      updatedAt = data['updatedAt'] as int? ?? 0,
      directAudio = data['directAudio'] == true {
    final rawFeatured = data['featured'];
    if (rawFeatured != null &&
        (rawFeatured is! List || rawFeatured.length > 80)) {
      throw const FormatException('精选作品数量无效');
    }
    featured = List.unmodifiable([
      for (final row in rawFeatured as List? ?? const [])
        Book(
          id,
          kind,
          bookLabel(row['title']),
          bookLabel(row['author']),
          resolve(endpoint, row['url'] as String),
          description: bookLabel(row['description'], 600),
        ),
    ]);
    if (name.isEmpty ||
        !const {'utf-8', 'gbk', 'gb2312', 'gb18030'}.contains(searchCharset) ||
        (searchForm.isNotEmpty && searchCharset != 'utf-8') ||
        (directAudio && kind != BookKind.audio) ||
        (format == BookFormat.featured && featured.isEmpty) ||
        (legado == null &&
            format == BookFormat.html &&
            (search.isEmpty ||
                (!search.contains('{key}') &&
                    !searchForm.values.any(
                      (value) => value.contains('{key}'),
                    )) ||
                [
                  'list',
                  'title',
                  'book',
                ].any((key) => !rules.containsKey(key)))) ||
        (legado == null &&
            format != BookFormat.feed &&
            [
              'chapters',
              'chapterTitle',
              'chapterUrl',
              if (!directAudio) 'content',
            ].any((key) => !rules.containsKey(key)))) {
      throw const FormatException('来源缺少名称或必要的搜索、目录及正文规则');
    }
    if (search.isNotEmpty) {
      resolve(endpoint, search.replaceAll('{key}', 'test'));
    }
    if (discover.isNotEmpty) resolve(endpoint, discover);
  }

  final String name, group, search, discover, sample, originNote, sourceKey;
  final String searchCharset;
  final int updatedAt;
  final Map<String, String> searchForm;
  final BookKind kind;
  final BookFormat format;
  final Uri endpoint;
  final bool builtin;
  final bool directAudio;
  final LegadoSource? legado;
  final List<LegadoCategory> discoveryCategories;
  late final List<Book> featured;
  final Map<String, String> rules;
  final Set<String> mediaHosts;

  late final String id = sourceKey.isEmpty
      ? legacyId
      : stableId('legado:${kind.name}:${format.name}:$sourceKey');

  late final String legacyId = _legacyId();

  String _legacyId() {
    final host = endpoint.host.replaceFirst(RegExp(r'^www\.'), '');
    return stableId(
      '${kind.name}:${format.name}:$host'
      '${format == BookFormat.feed ? endpoint.path + endpoint.query : ''}',
    );
  }

  bool get hasDiscovery =>
      format != BookFormat.html ||
      discover.isNotEmpty ||
      discoveryCategories.isNotEmpty ||
      (legado != null &&
          legado!.enabledExplore &&
          legado!.categories.isNotEmpty);

  bool get hasSearch =>
      format != BookFormat.html ||
      search.isNotEmpty ||
      (legado?.search.isNotEmpty ?? false);

  bool acceptsBookAddress(Uri uri) =>
      (legado?.bookUrlPattern.isNotEmpty ?? false) && uri.host == endpoint.host;

  Uri resolve(Uri base, String raw, {bool media = false}) {
    final target = base.resolve(raw.trim());
    return requestTarget(
      legado == null
          ? target
          : legacyBookUri(target, legacyQueryEncoding: true),
      media: media,
    );
  }

  Uri requestTarget(Uri target, {bool media = false}) {
    final uri = publicBookUri(
      target,
      legacyQueryEncoding: legado != null || searchCharset != 'utf-8',
    );
    if (uri.host != endpoint.host &&
        !(media && mediaHosts.contains(uri.host))) {
      throw const FormatException('来源地址超出已审查的域名范围');
    }
    return uri;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'group': group,
    'kind': kind.name,
    'format': format.name,
    'url': endpoint.toString(),
    'search': search,
    if (searchForm.isNotEmpty) 'searchForm': searchForm,
    if (searchCharset != 'utf-8') 'searchCharset': searchCharset,
    'discover': discover,
    if (discoveryCategories.isNotEmpty)
      'discoveryCategories': discoveryCategories
          .map((item) => item.toJson())
          .toList(),
    'sample': sample,
    'rules': rules,
    if (legado != null) 'legado': legado!.toJson(),
    'mediaHosts': mediaHosts.toList(),
    'originNote': originNote,
    if (sourceKey.isNotEmpty) 'sourceKey': sourceKey,
    if (updatedAt != 0) 'updatedAt': updatedAt,
    if (directAudio) 'directAudio': true,
    if (featured.isNotEmpty)
      'featured': featured.map((b) => b.toJson()).toList(),
  };

  static String _rule(Object? input, int limit) {
    if (input == null || input == '') return '';
    if (input is! String ||
        input.length > limit ||
        RegExp(
          r'[<\\\x00-\x1f\x7f]|@js\b|javascript:|\{\{|\}\}',
          caseSensitive: false,
        ).hasMatch(input)) {
      throw const FormatException('仅支持有界的静态来源规则');
    }
    return input.trim();
  }

  static Map<String, String> _rules(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map || raw.length > 40) throw const FormatException('规则数量无效');
    return Map.unmodifiable(
      {
        for (final entry in raw.entries)
          if (const {
            'list',
            'title',
            'author',
            'book',
            'description',
            'cover',
            'category',
            'wordCount',
            'latest',
            'rank',
            'updated',
            'discoverCover',
            'discoverRank',
            'discoverWordCount',
            'discoverLatest',
            'discoverUpdated',
            'nextDiscover',
            'infoDescription',
            'infoWordCount',
            'infoUpdated',
            'infoLatest',
            'infoCategory',
            'discoverCategory',
            'discoverList',
            'discoverTitle',
            'discoverAuthor',
            'discoverBook',
            'discoverDescription',
            'toc',
            'chapters',
            'chapterTitle',
            'chapterUrl',
            'nextToc',
            'content',
            'nextContent',
          }.contains(entry.key))
            entry.key as String: _rule(entry.value, 240),
      }..removeWhere((key, value) => value.isEmpty),
    );
  }

  static Map<String, String> _form(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map || raw.length > 16) {
      throw const FormatException('搜索表单字段数量无效');
    }
    return Map.unmodifiable(
      raw.map((key, value) {
        if (key is! String || !RegExp(r'^[\w.-]{1,64}$').hasMatch(key)) {
          throw const FormatException('搜索表单字段名无效');
        }
        return MapEntry(key, _rule(value, 512));
      }),
    );
  }

  static Set<String> _hosts(Object? raw) {
    if (raw == null) return const {};
    if (raw is! List || raw.length > 6) throw const FormatException('音频域名数量无效');
    return Set.unmodifiable(
      raw.map((host) {
        if (host is! String) throw const FormatException('音频域名无效');
        final uri = publicBookUri(Uri(scheme: 'https', host: host));
        return uri.host;
      }),
    );
  }
}

typedef BookDiscoveryPage = ({List<Book> books, String? next});

final class Book {
  const Book(
    this.sourceId,
    this.kind,
    this.title,
    this.author,
    this.uri, {
    this.description = '',
    this.cover = '',
    this.category = '',
    this.request = '',
    this.wordCount = '',
    this.latestChapter = '',
    this.updatedLabel = '',
    this.rankLabel = '',
  });
  final String sourceId, title, author, description, request, cover, category;
  final String wordCount, latestChapter, updatedLabel, rankLabel;
  final BookKind kind;
  final Uri uri;
  String get id => stableId('$sourceId:${request.isEmpty ? uri : request}');

  Map<String, Object?> toJson() => {
    'source': sourceId,
    'kind': kind.name,
    'title': title,
    'author': author,
    'url': uri.toString(),
    'description': description,
    'cover': cover,
    'category': category,
    if (wordCount.isNotEmpty) 'wordCount': wordCount,
    if (latestChapter.isNotEmpty) 'latestChapter': latestChapter,
    if (updatedLabel.isNotEmpty) 'updatedLabel': updatedLabel,
    if (rankLabel.isNotEmpty) 'rankLabel': rankLabel,
    if (request.isNotEmpty) 'request': request,
  };
  factory Book.fromJson(Map data) => Book(
    data['source'] as String,
    BookKind.values.byName(data['kind'] as String),
    bookLabel(data['title']),
    bookLabel(data['author']),
    Uri.parse(data['url'] as String),
    description: bookLabel(data['description'], 4000),
    cover: data['cover'] as String? ?? '',
    category: bookLabel(data['category']),
    request: data['request'] as String? ?? '',
    wordCount: bookLabel(data['wordCount']),
    latestChapter: bookLabel(data['latestChapter']),
    updatedLabel: bookLabel(data['updatedLabel']),
    rankLabel: bookLabel(data['rankLabel']),
  );

  Book withDetails(Book details) => Book(
    sourceId,
    kind,
    title,
    details.author.isEmpty ? author : details.author,
    uri,
    request: request,
    description: details.description.isEmpty
        ? description
        : details.description,
    cover: details.cover.isEmpty ? cover : details.cover,
    category: details.category.isEmpty ? category : details.category,
    rankLabel: rankLabel,
    wordCount: details.wordCount.isEmpty ? wordCount : details.wordCount,
    latestChapter: details.latestChapter.isEmpty
        ? latestChapter
        : details.latestChapter,
    updatedLabel: details.updatedLabel.isEmpty
        ? updatedLabel
        : details.updatedLabel,
  );
}

final class BookChapter {
  const BookChapter(this.title, this.uri, {this.body = '', this.request = ''});
  final String title;
  final Uri uri;
  final String body, request;
  String get id => stableId(request.isEmpty ? uri.toString() : request);

  Map<String, Object?> toJson() => {
    'title': title,
    'url': uri.toString(),
    if (request.isNotEmpty) 'request': request,
  };
  factory BookChapter.fromJson(Map data) => BookChapter(
    bookLabel(data['title']),
    Uri.parse(data['url'] as String),
    request: data['request'] as String? ?? '',
  );
}

String bookIdentity(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
  '',
);

/// Invalid optional metadata must not discard an otherwise readable book.
String bookCoverAddress(Uri base, String address) {
  if (address.trim().isEmpty || address.length > 4096) return '';
  try {
    var uri = base.resolve(address.trim());
    if (uri.scheme == 'http') uri = uri.replace(scheme: 'https');
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.host.isEmpty) {
      return '';
    }
    return uri.toString();
  } on FormatException {
    return '';
  }
}
