import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/media_http_client.dart';
import '../../../core/persistence/app_database.dart';
import '../../../media/gateway/offline_server.dart';
import '../../supervision/application/content_policy.dart';
import '../../supervision/domain/adult_source_evidence.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../domain/book.dart';
import 'audiobook_files.dart';
import 'book_client.dart';
import 'book_store.dart';
import 'local_book.dart';

typedef BookEdition = ({Book book, List<BookChapter> chapters});

final class BooksRepository {
  BooksRepository(
    AppDatabase db,
    Directory root,
    OfflineServer offline,
    this.policy,
    Future<void> Function(File, CancellationToken, String) validateAudio,
  ) : store = BookStore(db),
      _http = MediaHttpClient(maxConnectionsPerHost: 2) {
    audioFiles = AudiobookFiles(
      Directory(p.join(root.path, 'book_audio')),
      client,
      offline,
      validateAudio,
    );
  }

  final BookStore store;
  final ContentPolicy policy;
  final MediaHttpClient _http;
  late final client = BookClient(DocumentClient(_http));
  late final AudiobookFiles audioFiles;
  late final Future<List<BookSource>> _builtins = _loadBuiltins();
  final _verifiedSources = <String, BookSource>{};

  Future<List<BookSource>> _loadBuiltins() async {
    final data =
        jsonDecode(
              await rootBundle.loadString(
                'assets/catalogs/books/verified.json',
              ),
            )
            as List;
    final builtins = data
        .cast<Map>()
        .map((s) => BookSource.fromJson(s, builtin: true))
        .toList();
    _verifiedSources.addEntries(
      builtins.map((source) => MapEntry(source.id, source)),
    );
    return builtins;
  }

  bool kindAllowed(BookKind kind) =>
      !policy.supervision.corrupted &&
      !(kind == BookKind.audio && policy.supervision.enabled);

  bool sourceAllowed(BookSource source) =>
      kindAllowed(source.kind) &&
      !(policy.filterAdult &&
          ([source.endpoint.host, ...source.mediaHosts].any(knownAdultHost))) &&
      policy.textAllowed(
        '${source.name} ${source.endpoint.host}',
        category: source.group,
      ) &&
      !(policy.supervision.enabled && !source.builtin);

  bool bookAllowed(Book book) {
    final verified = _verifiedSources[book.sourceId];
    return kindAllowed(book.kind) &&
        (!policy.supervision.enabled ||
            (verified != null && sourceAllowed(verified))) &&
        !(policy.filterAdult && knownAdultHost(book.uri.host)) &&
        policy.textAllowed(
          '${book.title} ${book.author} ${book.description} ${book.uri.host}',
        );
  }

  Future<List<BookSourceEntry>> sources(BookKind kind) async =>
      (await store.sources(await _builtins))
          .where(
            (entry) =>
                entry.source.kind == kind &&
                sourceAllowed(entry.source) &&
                policy.textAllowed('', category: entry.group),
          )
          .toList();

  Future<BookSource> _active(Book book) async {
    if (!bookAllowed(book)) throw const ContentBlocked();
    final entry = (await sources(
      book.kind,
    )).where((e) => e.source.id == book.sourceId).firstOrNull;
    if (entry == null || !entry.enabled) throw const FormatException('请先启用该来源');
    return entry.source;
  }

  Future<void> saveSource(
    BookSource source,
    Map<String, Object?> updates,
  ) async {
    policy.supervision.require(SensitiveOperation.channels);
    if (!sourceAllowed(source)) throw const ContentBlocked();
    await store.saveSource(source, updates);
  }

  Future<String> sourceDocument(String address, CancellationToken token) async {
    policy.supervision.require(SensitiveOperation.channels);
    if (policy.supervision.enabled || policy.supervision.corrupted) {
      throw const ContentBlocked();
    }
    final uri = publicBookUri(Uri.parse(address));
    final response = await client.network.get(
      uri,
      maxBytes: 8 * 1024 * 1024,
      cancellation: token,
      validateTarget: (target) {
        if (publicBookUri(target).host != uri.host ||
            !policy.textAllowed(target.host) ||
            (policy.filterAdult && knownAdultHost(target.host))) {
          throw const FormatException('来源文件跳转超出允许范围');
        }
      },
    );
    return response.text;
  }

  Future<({int added, int duplicates})> importSources(
    List<BookSource> incoming,
  ) async {
    policy.supervision.require(SensitiveOperation.channels);
    final existing = (await store.sources(
      await _builtins,
    )).map((e) => e.source.id).toSet();
    var added = 0;
    var duplicates = 0;
    if (existing.length + incoming.length > 400) {
      throw const FormatException('来源管理最多保存 400 个渠道');
    }
    await store.db.atomic(() async {
      for (final source in incoming) {
        policy.supervision.require(SensitiveOperation.channels);
        if (!sourceAllowed(source)) continue;
        if (!existing.add(source.id)) {
          duplicates++;
          continue;
        }
        await store.saveSource(source, {'enabled': false});
        added++;
      }
    }, tables: {'app_meta'});
    return (added: added, duplicates: duplicates);
  }

  Future<void> removeSource(BookSource source) async {
    policy.supervision.require(SensitiveOperation.channels);
    if (source.builtin) {
      await store.saveSource(source, {'enabled': false});
    } else {
      await store.deleteSource(source);
    }
  }

  Future<void> probe(
    BookSource source,
    String query,
    CancellationToken token,
  ) async {
    policy.supervision.require(SensitiveOperation.channels);
    if (!sourceAllowed(source)) throw const ContentBlocked();
    final watch = Stopwatch()..start();
    var status = '';
    try {
      final books = await client.books(source, query, token);
      final book = books.where(bookAllowed).firstOrNull;
      if (book == null) throw const FormatException('没有匹配作品，试试该源中已知的书名');
      final chapters = await client.chapters(source, book, token);
      final chapter = chapters
          .where((c) => policy.textAllowed(c.title))
          .firstOrNull;
      if (chapter == null) throw const FormatException('目录没有可用章节');
      if (source.kind == BookKind.text) {
        final body = await client.text(source, chapter, token);
        if (body.trim().length < 40 || !policy.textAllowed(body)) {
          throw const FormatException('正文为空、过短或被内容策略拦截');
        }
      } else {
        final (uri, bytes) = await client.sampleAudio(source, chapter, token);
        audiobookExtension(
          bytes,
          isM4b: uri.path.toLowerCase().endsWith('.m4b'),
        );
      }
      status = '可用 · ${watch.elapsedMilliseconds} ms';
    } on FormatException catch (error) {
      status = error.message;
    } on RemoteFailure catch (error) {
      status = error.message;
    } on Exception {
      status = '检测失败';
    }
    token.check();
    await saveSource(source, {
      'health': status,
      'checkedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<({List<Book> books, int failed})> find(
    BookKind kind,
    String query,
    CancellationToken token, {
    String? group,
    bool favorites = false,
  }) async {
    if (!kindAllowed(kind)) throw const ContentBlocked();
    if (query.isNotEmpty && !policy.textAllowed(query)) {
      throw const ContentBlocked();
    }
    final selected =
        (await sources(kind))
            .where(
              (e) =>
                  e.enabled &&
                  (group == null || group == e.group) &&
                  (!favorites || e.favorite),
            )
            .toList()
          ..sort((a, b) => (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));
    var failed = 0;
    final results = <Book>[];
    for (var start = 0; start < selected.length; start += 4) {
      token.check();
      final batch = await Future.wait(
        selected.skip(start).take(4).map((entry) async {
          try {
            return await client.books(entry.source, query, token);
          } on Exception {
            failed++;
            return <Book>[];
          }
        }),
      );
      results.addAll(batch.expand((books) => books));
    }
    token.check();
    return (books: results.where(bookAllowed).toList(), failed: failed);
  }

  Future<List<BookChapter>> chapters(
    Book book,
    CancellationToken token, {
    bool refresh = false,
  }) async {
    if (!bookAllowed(book)) throw const ContentBlocked();
    final saved = await store.entry(book);
    if (saved != null && saved.chapters.isNotEmpty && !refresh) {
      return saved.chapters.where((c) => policy.textAllowed(c.title)).toList();
    }
    final source = await _active(book);
    final chapters = (await client.chapters(
      source,
      book,
      token,
    )).where((c) => policy.textAllowed(c.title)).toList();
    token.check();
    if (!sourceAllowed(source) || !bookAllowed(book)) {
      throw const ContentBlocked();
    }
    return chapters;
  }

  Future<List<BookEdition>> alternatives(
    Book book,
    CancellationToken token,
  ) async {
    final title = bookIdentity(book.title);
    final author = bookIdentity(book.author);
    if (author.isEmpty) return [];
    final results = await find(book.kind, book.title, token);
    final alternatives = <BookEdition>[];
    for (final candidate
        in results.books
            .where(
              (other) =>
                  other.sourceId != book.sourceId &&
                  bookIdentity(other.title) == title &&
                  bookIdentity(other.author) == author,
            )
            .take(5)) {
      token.check();
      try {
        final catalog = await chapters(candidate, token);
        if (catalog.isNotEmpty) {
          alternatives.add((book: candidate, chapters: catalog));
        }
      } on Exception {
        continue;
      }
    }
    token.check();
    return alternatives;
  }

  BookChapter? matchingChapter(
    List<BookChapter> chapters,
    BookChapter reference,
  ) {
    final key = bookIdentity(reference.title);
    if (key.isEmpty) return null;
    final matches = chapters
        .where((chapter) => bookIdentity(chapter.title) == key)
        .take(2)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  void requireBook(Book book, BookChapter chapter) {
    if (!bookAllowed(book) || !policy.textAllowed(chapter.title)) {
      throw const ContentBlocked();
    }
  }

  Future<String> readText(
    Book book,
    BookChapter chapter,
    CancellationToken token,
  ) async {
    requireBook(book, chapter);
    var body = await store.text(book, chapter);
    if (body == null) {
      final source = await _active(book);
      body = await client.text(source, chapter, token);
      if (!sourceAllowed(source)) throw const ContentBlocked();
    }
    token.check();
    requireBook(book, chapter);
    if (!policy.textAllowed(body)) throw const ContentBlocked();
    return body;
  }

  Future<void> download(
    Book book,
    BookChapter chapter,
    CancellationToken token, {
    List<BookEdition> alternatives = const [],
  }) async {
    requireBook(book, chapter);
    final candidates = [(book, chapter)];
    for (final edition in alternatives) {
      final match = matchingChapter(edition.chapters, chapter);
      if (match != null) candidates.add((edition.book, match));
    }
    Object? last;
    for (final (candidate, part) in candidates) {
      token.check();
      try {
        if (book.kind == BookKind.text) {
          final body = await readText(candidate, part, token);
          requireBook(book, chapter);
          await store.saveText(book, chapter, body);
        } else {
          final source = await _active(candidate);
          await audioFiles.download(source, book, part, token, () {
            requireBook(book, chapter);
            requireBook(candidate, part);
            if (!sourceAllowed(source)) throw const ContentBlocked();
          }, targetChapter: chapter);
        }
        return;
      } on Exception catch (error) {
        last = error;
      }
    }
    token.check();
    throw last ?? const FormatException('没有可用章节');
  }

  Future<Book> importLocal(File file) async {
    const max = 12 * 1024 * 1024;
    final name = p.basename(file.path);
    if (!{'.txt', '.epub'}.contains(p.extension(name).toLowerCase())) {
      throw const FormatException('仅支持 TXT 和 EPUB');
    }
    if (policy.supervision.enabled || !kindAllowed(BookKind.text)) {
      throw const ContentBlocked();
    }
    final length = await file.length();
    if (length == 0 || length > max) {
      throw const FormatException('电子书文件需小于 12 MiB');
    }
    final bytes = await file
        .openRead(0, max + 1)
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    if (bytes.length > max) throw const FormatException('电子书文件需小于 12 MiB');
    final parsed = await Isolate.run(() => parseLocalBook(name, bytes));
    if (parsed.sections.isEmpty || parsed.sections.length > 4000) {
      throw const FormatException('电子书正文为空或章节过多');
    }
    final book = Book(
      'local',
      BookKind.text,
      parsed.title,
      parsed.author,
      Uri(scheme: 'book', path: sha256.convert(bytes).toString()),
    );
    if (!bookAllowed(book) ||
        parsed.sections.any(
          (section) =>
              !policy.textAllowed(section.title) ||
              !policy.textAllowed(section.text),
        )) {
      throw const ContentBlocked();
    }
    final contents = {
      for (final (index, section) in parsed.sections.indexed)
        BookChapter(section.title, book.uri.replace(fragment: '$index')):
            section.text,
    };
    await store.db.atomic(() async {
      await store.saveTexts(book, contents);
      await store.saveBook(
        book,
        chapters: contents.keys.toList(),
        favorite: true,
      );
    }, tables: {'app_meta'});
    return book;
  }

  Future<void> close() async {
    _http.close();
    await audioFiles.close();
  }
}
