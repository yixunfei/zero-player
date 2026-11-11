import 'dart:io';

import '../../../core/network/network_target_policy.dart';
import '../../sources/domain/video_source.dart';

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

Uri publicBookUri(Uri uri) {
  NetworkTargetPolicy.validateUri(uri);
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

final class BookSource {
  BookSource.fromJson(Map data, {this.builtin = false})
    : name = bookLabel(data['name']),
      group = bookLabel(data['group'], 60),
      kind = BookKind.values.byName(data['kind'] as String),
      format = BookFormat.values.byName(data['format'] as String),
      endpoint = publicBookUri(Uri.parse(data['url'] as String)),
      search = _rule(data['search'], 1024),
      discover = _rule(data['discover'], 1024),
      sample = bookLabel(data['sample'], 80),
      rules = _rules(data['rules']),
      mediaHosts = _hosts(data['mediaHosts']),
      originNote = bookLabel(data['originNote'], 240),
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
        (directAudio && kind != BookKind.audio) ||
        (format == BookFormat.featured && featured.isEmpty) ||
        (format == BookFormat.html &&
            (!search.contains('{key}') ||
                [
                  'list',
                  'title',
                  'book',
                ].any((key) => !rules.containsKey(key)))) ||
        (format != BookFormat.feed &&
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

  final String name, group, search, discover, sample, originNote;
  final BookKind kind;
  final BookFormat format;
  final Uri endpoint;
  final bool builtin;
  final bool directAudio;
  late final List<Book> featured;
  final Map<String, String> rules;
  final Set<String> mediaHosts;

  String get id {
    final host = endpoint.host.replaceFirst(RegExp(r'^www\.'), '');
    return stableId(
      '${kind.name}:${format.name}:$host'
      '${format == BookFormat.feed ? endpoint.path + endpoint.query : ''}',
    );
  }

  Uri resolve(Uri base, String raw, {bool media = false}) {
    final uri = publicBookUri(base.resolve(raw.trim()));
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
    'discover': discover,
    'sample': sample,
    'rules': rules,
    'mediaHosts': mediaHosts.toList(),
    'originNote': originNote,
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
    if (raw is! Map || raw.length > 24) throw const FormatException('规则数量无效');
    return Map.unmodifiable(
      {
        for (final entry in raw.entries)
          if (const {
            'list',
            'title',
            'author',
            'book',
            'description',
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

final class Book {
  const Book(
    this.sourceId,
    this.kind,
    this.title,
    this.author,
    this.uri, {
    this.description = '',
  });
  final String sourceId, title, author, description;
  final BookKind kind;
  final Uri uri;
  String get id => stableId('$sourceId:$uri');

  Map<String, Object?> toJson() => {
    'source': sourceId,
    'kind': kind.name,
    'title': title,
    'author': author,
    'url': uri.toString(),
    'description': description,
  };
  factory Book.fromJson(Map data) => Book(
    data['source'] as String,
    BookKind.values.byName(data['kind'] as String),
    bookLabel(data['title']),
    bookLabel(data['author']),
    Uri.parse(data['url'] as String),
    description: bookLabel(data['description'], 600),
  );
}

final class BookChapter {
  const BookChapter(this.title, this.uri, {this.body = ''});
  final String title;
  final Uri uri;
  final String body;
  String get id => stableId(uri.toString());

  Map<String, Object?> toJson() => {'title': title, 'url': uri.toString()};
  factory BookChapter.fromJson(Map data) =>
      BookChapter(bookLabel(data['title']), Uri.parse(data['url'] as String));
}

String bookIdentity(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
  '',
);
