import 'dart:convert';

import 'package:xml/xml.dart';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/header_policy.dart';
import '../domain/book.dart';
import 'book_html.dart';

final class BookClient {
  const BookClient(this.network);
  final DocumentClient network;

  Future<Document> fetch(
    BookSource source,
    Uri uri,
    CancellationToken token, {
    bool media = false,
    int maxBytes = 2 * 1024 * 1024,
  }) {
    return network.get(
      uri,
      cancellation: token,
      maxBytes: maxBytes,
      networkTimeout: Duration(seconds: media ? 90 : 12),
      validateTarget: (target) =>
          source.resolve(source.endpoint, target.toString(), media: media),
    );
  }

  Future<List<Book>> books(
    BookSource source,
    String query,
    CancellationToken token,
  ) async {
    if (source.format == BookFormat.featured) {
      final key = bookIdentity(query);
      return source.featured
          .where(
            (book) => bookIdentity(
              '${book.title} ${book.author} ${book.description}',
            ).contains(key),
          )
          .toList();
    }
    if (source.format == BookFormat.feed) {
      final feed = await _feed(source, token);
      final book = feed.$1;
      final text = bookIdentity(
        '${book.title} ${book.author} ${book.description}',
      );
      return query.isEmpty || text.contains(bookIdentity(query)) ? [book] : [];
    }
    final discovery = query.isEmpty;
    final path = discovery
        ? source.discover
        : source.search.replaceAll('{key}', Uri.encodeComponent(query));
    if (path.isEmpty) return [];
    final response = await fetch(
      source,
      source.resolve(source.endpoint, path),
      token,
    );
    final document = parseBookHtml(response.text);
    String rule(String key) {
      final discoverKey = 'discover${key[0].toUpperCase()}${key.substring(1)}';
      return (discovery ? source.rules[discoverKey] : null) ??
          source.rules[key] ??
          '';
    }

    final results = <Uri, Book>{};
    for (final row in document.querySelectorAll(rule('list')).take(80)) {
      final title = bookLabel(bookField(row, rule('title')));
      final link = bookField(row, rule('book'));
      if (title.isEmpty || link.isEmpty) continue;
      try {
        final uri = source.resolve(response.uri, link);
        results.putIfAbsent(
          uri,
          () => Book(
            source.id,
            source.kind,
            title,
            bookLabel(
              bookField(
                row,
                rule('author'),
              ).replaceFirst(RegExp(r'^作者[:：]\s*'), ''),
            ),
            uri,
            description: bookLabel(bookField(row, rule('description')), 600),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return results.values.toList();
  }

  Future<List<BookChapter>> chapters(
    BookSource source,
    Book book,
    CancellationToken token,
  ) async {
    if (source.format == BookFormat.feed) {
      return (await _feed(source, token)).$2;
    }
    final chapters = <Uri, BookChapter>{};
    final visited = <Uri>{};
    var next = book.uri;
    for (var page = 0; page < 12 && visited.add(next); page++) {
      final response = await fetch(source, next, token);
      final document = parseBookHtml(response.text);
      final toc = page == 0
          ? bookField(document, source.rules['toc'] ?? '')
          : '';
      if (toc.isNotEmpty) {
        final target = source.resolve(response.uri, toc);
        if (!visited.contains(target)) {
          next = target;
          continue;
        }
      }
      for (final row
          in document
              .querySelectorAll(source.rules['chapters']!)
              .take(4000 - chapters.length)) {
        final title = bookLabel(bookField(row, source.rules['chapterTitle']!));
        final link = bookField(row, source.rules['chapterUrl']!);
        if (title.isEmpty || link.isEmpty) continue;
        try {
          final uri = source.resolve(
            response.uri,
            link,
            media: source.directAudio,
          );
          chapters.putIfAbsent(uri, () => BookChapter(title, uri));
        } on FormatException {
          continue;
        }
      }
      final more = bookField(document, source.rules['nextToc'] ?? '');
      if (more.isEmpty || chapters.length == 4000) break;
      next = source.resolve(response.uri, more);
    }
    return chapters.values.toList();
  }

  Future<String> text(
    BookSource source,
    BookChapter chapter,
    CancellationToken token,
  ) async {
    if (source.format == BookFormat.feed) {
      if (chapter.body.isNotEmpty) return chapter.body;
      final feed = await _feed(source, token);
      final body = feed.$2.where((c) => c.id == chapter.id).firstOrNull?.body;
      if (body == null || body.isEmpty) {
        throw const FormatException('订阅未提供该篇正文');
      }
      return body;
    }
    final parts = <String>[];
    final visited = <Uri>{};
    var next = chapter.uri;
    for (var page = 0; page < 10 && visited.add(next); page++) {
      final response = await fetch(source, next, token);
      final document = parseBookHtml(response.text);
      final body = bookField(document, source.rules['content']!, long: true);
      if (body.isEmpty) throw const FormatException('来源未返回章节正文');
      if (!parts.contains(body)) parts.add(body);
      final more = bookField(document, source.rules['nextContent'] ?? '');
      if (more.isEmpty) break;
      next = source.resolve(response.uri, more);
    }
    final result = parts.join('\n\n');
    if (result.length > 500000) throw const FormatException('章节正文超过大小限制');
    return result;
  }

  Future<Uri> audio(
    BookSource source,
    BookChapter chapter,
    CancellationToken token,
  ) async {
    if (source.format == BookFormat.feed || source.directAudio) {
      return source.resolve(
        source.endpoint,
        chapter.uri.toString(),
        media: true,
      );
    }
    final response = await fetch(source, chapter.uri, token);
    final address = bookField(
      parseBookHtml(response.text),
      source.rules['content']!,
    );
    if (address.isEmpty) throw const FormatException('来源未提供直连音频');
    return source.resolve(response.uri, address, media: true);
  }

  Future<(Uri, List<int>)> sampleAudio(
    BookSource source,
    BookChapter chapter,
    CancellationToken token,
  ) async {
    final uri = await audio(source, chapter, token);
    final payload = await network.http.open(
      uri,
      policy: HeaderPolicy({uri: const {}}),
      range: 'bytes=0-127',
      cancellation: token,
      validateTarget: (target) =>
          source.resolve(source.endpoint, target.toString(), media: true),
    );
    if (!{200, 206}.contains(payload.response.statusCode)) {
      await payload.body.take(0).drain<void>();
      throw const FormatException('音频地址请求失败');
    }
    return (
      payload.uri,
      await payload.body.expand((chunk) => chunk).take(64).toList(),
    );
  }

  Future<(Book, List<BookChapter>)> _feed(
    BookSource source,
    CancellationToken token,
  ) async {
    final response = await fetch(source, source.endpoint, token);
    final raw = response.text;
    if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(raw)) {
      throw const FormatException('订阅不能包含 XML 实体或文档类型声明');
    }
    final root = XmlDocument.parse(raw).rootElement;
    final atom = root.name.local == 'feed';
    final channel = atom ? root : root.getElement('channel');
    if (channel == null) throw const FormatException('地址没有返回 RSS 或 Atom');
    String field(XmlElement node, String key) =>
        node.childElements
            .where((e) => e.name.local == key)
            .firstOrNull
            ?.innerText ??
        '';
    final title = bookLabel(field(channel, 'title'));
    if (title.isEmpty) throw const FormatException('订阅缺少标题');
    final author = bookLabel(field(channel, 'author'));
    final book = Book(
      source.id,
      source.kind,
      title,
      author,
      source.endpoint,
      description: bookLabel(
        plainBookText(
          parseBookHtml(field(channel, atom ? 'subtitle' : 'description')),
        ),
        600,
      ),
    );
    final items = <Uri, BookChapter>{};
    for (final entry
        in channel.childElements
            .where((e) => e.name.local == (atom ? 'entry' : 'item'))
            .take(500)) {
      final name = bookLabel(field(entry, 'title'));
      if (name.isEmpty) continue;
      if (source.kind == BookKind.audio) {
        for (final element in entry.childElements.where(
          (e) =>
              e.name.local == 'enclosure' ||
              (e.name.local == 'link' && e.getAttribute('rel') == 'enclosure'),
        )) {
          final path = element.getAttribute(atom ? 'href' : 'url') ?? '';
          if (path.isEmpty) continue;
          try {
            final uri = source.resolve(response.uri, path, media: true);
            items.putIfAbsent(uri, () => BookChapter(name, uri));
            break;
          } on FormatException {
            continue;
          }
        }
      } else {
        final rawBody = [
          field(entry, 'encoded'),
          field(entry, 'content'),
          field(entry, 'description'),
          field(entry, 'summary'),
        ].firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
        final body = plainBookText(parseBookHtml(rawBody));
        if (body.isEmpty) continue;
        final id = [
          field(entry, 'guid'),
          field(entry, 'id'),
          field(entry, 'link'),
          name,
        ].firstWhere((value) => value.trim().isNotEmpty);
        final uri = source.endpoint.replace(
          fragment: base64Url.encode(
            utf8.encode(id.length > 512 ? id.substring(0, 512) : id),
          ),
        );
        items.putIfAbsent(uri, () => BookChapter(name, uri, body: body));
      }
    }
    return (book, items.values.toList());
  }
}
