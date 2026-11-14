import '../../../../core/network/cancellation_token.dart';
import '../../../../core/network/document_client.dart';
import '../../domain/book.dart';
import '../../domain/book_search.dart';
import '../../domain/legado_source.dart';
import 'legado_request.dart';
import 'legado_rule_tokens.dart';
import 'legado_script.dart';
import 'legado_worker.dart';

final class LegadoBookClient {
  const LegadoBookClient(this.network);
  final DocumentClient network;

  Future<List<LegadoCategory>> categories(
    BookSource source,
    CancellationToken token,
  ) async {
    final spec = source.legado!;
    if (!spec.enabledExplore || source.format == BookFormat.feed) return [];
    final categories = <(String, String), LegadoCategory>{};
    Exception? failure;
    for (final category in spec.categories) {
      try {
        final entries =
            legadoScriptMarker.matchAsPrefix(category.address) == null
            ? [category]
            : (await _run(
                LegadoJob(
                  source,
                  source.endpoint,
                  LegadoOperation.discovery,
                  address: category.address,
                ),
                token,
              )).categories;
        for (final item in entries) {
          final grouped = category.group.isEmpty || item.group.isNotEmpty
              ? item
              : LegadoCategory(item.title, item.address, group: category.group);
          categories.putIfAbsent((
            grouped.group,
            grouped.address,
          ), () => grouped);
        }
      } on Exception catch (error) {
        token.check();
        failure = error;
      }
    }
    if (categories.isEmpty && failure != null) throw failure;
    return categories.values.toList();
  }

  Future<BookDiscoveryPage> discover(
    BookSource source,
    CancellationToken token, {
    LegadoCategory? category,
    int page = 1,
    String? cursor,
  }) async {
    final options = category != null
        ? [category.address]
        : (await categories(source, token)).map((item) => item.address);
    final request = cursor == null
        ? await _firstAddress(source, options, token, page: page)
        : LegadoRequest.parse(source, source.endpoint, cursor, page: page);
    if (request == null) return (books: <Book>[], next: null);
    final parsed = await _list(
      source,
      request,
      token,
      page: page,
      discovery: true,
    );
    String? next;
    if (parsed.books.isNotEmpty) {
      final link = parsed.links.firstOrNull;
      final nextRequest = link != null
          ? _link(source, parsed.uri, link, page + 1)
          : (source.legado!.rules['nextExplore'] ?? '').isEmpty &&
                category?.paginated == true
          ? await _firstAddress(source, options, token, page: page + 1)
          : null;
      if (nextRequest?.targetKey != request.targetKey) {
        next = nextRequest?.targetKey;
      }
    }
    return (books: parsed.books, next: next);
  }

  Future<Document> feedDocument(
    BookSource source,
    CancellationToken token,
  ) async {
    final address = source.legado!.search;
    final request = await _firstAddress(source, [address], token);
    if (request == null) throw const FormatException('Legado 订阅未提供可用地址');
    return _fetch(source, request, token);
  }

  Future<List<Book>> books(
    BookSource source,
    String query,
    CancellationToken token, {
    LegadoCategory? category,
    int page = 1,
    Uri? bookAddress,
  }) async {
    final spec = source.legado!;
    if (source.format == BookFormat.feed) {
      final book = Book(
        source.id,
        source.kind,
        source.name,
        '',
        source.endpoint,
      );
      final key = bookIdentity(query);
      if (key.isEmpty || bookIdentity(source.name).contains(key)) return [book];
      final articles = await chapters(source, book, token);
      return articles.any((item) => bookIdentity(item.title).contains(key))
          ? [book]
          : [];
    }
    if (bookAddress != null) return _openAddress(source, bookAddress, token);
    final discovery = query.isEmpty || spec.search.isEmpty;
    final addresses = !discovery
        ? [spec.search]
        : category != null
        ? [category.address]
        : (await categories(source, token)).map((item) => item.address);
    final request = await _firstAddress(
      source,
      addresses,
      token,
      query: query,
      page: page,
    );
    if (request == null) return [];
    final parsed = await _list(
      source,
      request,
      token,
      query: query,
      page: page,
      discovery: discovery,
    );
    if (discovery && query.trim().isNotEmpty) {
      final match = BookSearchQuery(query, BookSearchField.all);
      return parsed.books.where((book) => match.rank(book) != null).toList();
    }
    return parsed.books;
  }

  Future<({Uri uri, List<Book> books, List<String> links})> _list(
    BookSource source,
    LegadoRequest request,
    CancellationToken token, {
    String query = '',
    required int page,
    required bool discovery,
  }) async {
    final document = await _fetch(source, request, token);
    final parsed = await _run(
      LegadoJob(
        source,
        document.uri,
        LegadoOperation.books,
        input: document.text,
        address: request.reference,
        query: query,
        page: page,
        discovery: discovery,
      ),
      token,
    );
    return (uri: document.uri, books: parsed.books, links: parsed.links);
  }

  Future<List<Book>> _openAddress(
    BookSource source,
    Uri address,
    CancellationToken token,
  ) async {
    if (!source.acceptsBookAddress(address)) return [];
    final safe = source.requestTarget(address);
    final match = await _run(
      LegadoJob(source, safe, LegadoOperation.matchBookUrl),
      token,
    );
    if (!match.matches) return [];
    final request = LegadoRequest.parse(source, source.endpoint, '$safe');
    final document = await _fetch(source, request, token);
    return (await _run(
      LegadoJob(
        source,
        document.uri,
        LegadoOperation.details,
        input: document.text,
      ),
      token,
    )).books;
  }

  Future<List<BookChapter>> chapters(
    BookSource source,
    Book book,
    CancellationToken token,
  ) async {
    final articles = source.format == BookFormat.feed;
    final first = articles
        ? await _firstAddress(source, [
            source.legado!.search,
            ...source.legado!.explore,
          ], token)
        : _stored(source, book.uri, book.request);
    if (first == null) return [];
    final chapters = <String, BookChapter>{};
    final visited = <String>{};
    final queue = <LegadoRequest>[first];
    for (
      var page = 1;
      page <= 12 && queue.isNotEmpty && chapters.length < 4000;
      page++
    ) {
      final next = queue.removeAt(0);
      if (!visited.add(next.targetKey)) {
        page--;
        continue;
      }
      final document = await _fetch(source, next, token);
      final result = await _run(
        LegadoJob(
          source,
          document.uri,
          articles ? LegadoOperation.articles : LegadoOperation.toc,
          input: document.text,
          page: page,
          book: book,
        ),
        token,
      );
      for (final item in result.chapters.take(4000 - chapters.length)) {
        chapters.putIfAbsent(item.id, () => item);
      }
      for (final address in result.links) {
        final request = _link(source, document.uri, address, page + 1);
        if (request != null && !visited.contains(request.targetKey)) {
          queue.add(request);
        }
      }
    }
    return chapters.values.toList();
  }

  Future<Book> details(
    BookSource source,
    Book book,
    CancellationToken token,
  ) async {
    final rules = source.legado!.rules;
    if (!rules.keys.any((key) => key.startsWith('info'))) return book;
    final request = _stored(source, book.uri, book.request);
    final document = await _fetch(source, request, token);
    final result = await _run(
      LegadoJob(
        source,
        document.uri,
        LegadoOperation.details,
        input: document.text,
        book: book,
        address: book.request,
      ),
      token,
    );
    final details = result.books.firstOrNull;
    return details == null ? book : book.withDetails(details);
  }

  Future<String> text(
    BookSource source,
    BookChapter chapter,
    CancellationToken token, {
    Book? book,
  }) async {
    if (chapter.body.isNotEmpty) return chapter.body;
    if (source.format == BookFormat.feed &&
        (source.legado!.rules['content'] ?? '').isEmpty) {
      final series =
          book ??
          Book(source.id, source.kind, source.name, '', source.endpoint);
      final item = (await chapters(
        source,
        series,
        token,
      )).where((item) => item.id == chapter.id).firstOrNull;
      if (item != null && item.body.isNotEmpty) return item.body;
      throw const FormatException('订阅没有提供此篇正文规则');
    }
    var next = _stored(source, chapter.uri, chapter.request);
    final visited = <String>{};
    final parts = <String>[];
    var length = 0;
    for (var page = 1; page <= 10 && visited.add(next.targetKey); page++) {
      final document = await _fetch(source, next, token);
      if (document.contentType?.toLowerCase().startsWith('image/') == true) {
        throw const FormatException('章节仅提供图片，文本阅读器无法打开');
      }
      final result = await _run(
        LegadoJob(
          source,
          document.uri,
          LegadoOperation.content,
          input: document.text,
          page: page,
          book: book,
          chapter: chapter,
        ),
        token,
      );
      if (result.content.isEmpty) {
        throw const FormatException('Legado 规则未提取到正文');
      }
      if (!parts.contains(result.content)) {
        length += result.content.length;
        if (length > 500000) throw const FormatException('章节正文超过大小限制');
        parts.add(result.content);
      }
      final more = result.links
          .map((link) => _link(source, document.uri, link, page + 1))
          .whereType<LegadoRequest>()
          .where((link) => !visited.contains(link.targetKey))
          .firstOrNull;
      if (more == null) break;
      if (page == 10) throw const FormatException('章节分页超过限制，正文未完整获取');
      next = more;
    }
    return parts.join('\n\n');
  }

  Future<Uri> audio(
    BookSource source,
    BookChapter chapter,
    CancellationToken token, {
    Book? book,
  }) async {
    if ((source.legado!.rules['content'] ?? '').isEmpty) {
      return source.requestTarget(chapter.uri, media: true);
    }
    final document = await _fetch(
      source,
      _stored(source, chapter.uri, chapter.request),
      token,
    );
    final result = await _run(
      LegadoJob(
        source,
        document.uri,
        LegadoOperation.audio,
        input: document.text,
        book: book,
        chapter: chapter,
      ),
      token,
    );
    if (result.links.isEmpty) {
      throw const FormatException('Legado 规则未提取到已授权域名的音频');
    }
    return source.requestTarget(Uri.parse(result.links.first), media: true);
  }

  Future<LegadoRequest?> _firstAddress(
    BookSource source,
    Iterable<String> options,
    CancellationToken token, {
    String query = '',
    int page = 1,
  }) async {
    FormatException? invalid;
    for (final address in options.where((address) => address.isNotEmpty)) {
      token.check();
      try {
        final links = legadoScriptMarker.hasMatch(address)
            ? (await _run(
                LegadoJob(
                  source,
                  source.endpoint,
                  LegadoOperation.address,
                  address: address,
                  query: query,
                  page: page,
                ),
                token,
              )).links
            : [address];
        for (final value in links) {
          try {
            return LegadoRequest.parse(
              source,
              source.endpoint,
              value,
              key: query,
              page: page,
            );
          } on FormatException catch (error) {
            invalid = error;
          }
        }
      } on FormatException catch (error) {
        invalid = error;
      }
    }
    if (invalid != null) throw invalid;
    return null;
  }

  Future<LegadoPage> _run(LegadoJob job, CancellationToken token) async {
    final documents = <String, String>{};
    for (var attempt = 0; ; attempt++) {
      try {
        return await runLegadoJob(job.withDocuments(documents), token);
      } on LegadoNeedsDocument catch (pending) {
        if (attempt >= 3 || documents.containsKey(pending.address)) {
          throw const FormatException('Legado 脚本请求超过限制');
        }
        final request = LegadoRequest.parse(
          job.source,
          job.uri,
          pending.address,
        );
        if (request.form != null || request.json != null) {
          throw const FormatException('Legado 脚本辅助请求仅支持同站 GET');
        }
        documents[pending.address] = (await _fetch(
          job.source,
          request,
          token,
        )).text;
      }
    }
  }

  Future<Document> _fetch(
    BookSource source,
    LegadoRequest request,
    CancellationToken token,
  ) {
    final uri = source.requestTarget(request.uri);
    if (request.json case final Map<String, Object?> body) {
      return network.postJson(
        uri,
        body,
        headers: request.headers,
        cancellation: token,
      );
    }
    if (request.form case final Map<String, String> body) {
      return network.postForm(
        uri,
        body,
        headers: request.headers,
        cancellation: token,
        encoding: request.encoding,
      );
    }
    return network.get(
      uri,
      headers: request.headers,
      networkTimeout: const Duration(seconds: 12),
      cancellation: token,
      validateTarget: source.requestTarget,
    );
  }
}

LegadoRequest _stored(BookSource source, Uri uri, String reference) {
  final safe = source.requestTarget(uri);
  final request = LegadoRequest.parse(
    source,
    safe,
    reference.isEmpty ? '$safe' : reference,
  );
  if (request.uri != safe) throw const FormatException('已保存的 Legado 请求地址不一致');
  return request;
}

LegadoRequest? _link(BookSource source, Uri base, String raw, int page) {
  try {
    return LegadoRequest.parse(source, base, raw, page: page);
  } on FormatException {
    return null;
  }
}
