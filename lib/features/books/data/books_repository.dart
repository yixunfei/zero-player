import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import '../domain/book_search.dart';
import '../domain/legado_source.dart';
import 'aoaostar_book_catalog.dart';
import 'audiobook_files.dart';
import 'book_client.dart';
import 'book_import.dart';
import 'book_source_links.dart';
import 'book_store.dart';
import 'local_book.dart';
import 'qidian_catalog.dart';
import 'rich_book.dart';

typedef BookEdition = ({Book book, List<BookChapter> chapters});
typedef BookImportChanges = ({
  int added,
  int updated,
  int duplicates,
  int skipped,
});

typedef BookSearchUpdate = ({
  String? sourceId,
  List<Book> books,
  int completed,
  int total,
  bool failed,
  int? latencyMs,
});

bool _retiredNewsHost(String host) => const [
  'ithome.com',
  'sspai.com',
  'ifanr.com',
].any((domain) => host == domain || host.endsWith('.$domain'));

Uri? _bookAddress(String query) {
  final uri = Uri.tryParse(query);
  if (uri == null ||
      !uri.hasAuthority ||
      !const {'http', 'https'}.contains(uri.scheme)) {
    return null;
  }
  return legacyBookUri(uri);
}

final class BooksRepository {
  BooksRepository(
    AppDatabase db,
    Directory root,
    OfflineServer offline,
    this.policy,
    Future<void> Function(File, CancellationToken, String) validateAudio,
  ) : store = BookStore(db),
      _http = MediaHttpClient(
        maxConnectionsPerHost: 2,
        allowLegacyQueryEncoding: true,
      ) {
    documents = Directory(p.join(root.path, 'book_documents'));
    audioFiles = AudiobookFiles(
      Directory(p.join(root.path, 'book_audio')),
      client,
      offline,
      validateAudio,
    );
  }

  late final Directory documents;
  File documentFile(Book book, String extension) =>
      File(p.join(documents.path, '${book.id}.$extension'));
  final BookStore store;
  final ContentPolicy policy;
  final MediaHttpClient _http;
  late final client = BookClient(DocumentClient(_http));
  late final qidian = QidianCatalog(client.network, policy, store.db);
  late final AudiobookFiles audioFiles;
  late final Future<List<BookSource>> _builtins = _loadBuiltins();
  final _verifiedSources = <String, BookSource>{};
  final _refreshingSubscriptions = <String>{};
  Future<void>? _seeding;

  Future<void> ensureCatalog() async {
    if (policy.supervision.enabled || policy.supervision.corrupted) return;
    final running = _seeding ??= _seedCatalog();
    try {
      await running;
    } finally {
      if (identical(_seeding, running)) _seeding = null;
    }
  }

  Future<void> _seedCatalog() async {
    final catalog = await AoaoStarBookCatalog.load();
    if (await store.read('books_catalog_revision') == catalog.revision) return;
    await importSources(
      (await catalog.read()).sources,
      fromCatalog: true,
      catalogRevision: catalog.revision,
    );
  }

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
      (source.kind != BookKind.text ||
          !_retiredNewsHost(source.endpoint.host)) &&
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
        (book.kind != BookKind.text || !_retiredNewsHost(book.uri.host)) &&
        (!policy.supervision.enabled ||
            (verified != null && sourceAllowed(verified))) &&
        !(policy.filterAdult && knownAdultHost(book.uri.host)) &&
        policy.textAllowed(
          '${book.title} ${book.author} ${book.description} ${book.category} ${book.uri.host}',
        );
  }

  Future<List<BookSourceEntry>> sources(
    BookKind kind, {
    bool enabledOnly = false,
  }) async {
    final blocked = await store.blockedSources();
    return (await store.sources(await _builtins, enabledOnly: enabledOnly))
        .where(
          (entry) =>
              entry.source.kind == kind &&
              !blocked.containsKey(entry.source.id) &&
              sourceAllowed(entry.source) &&
              policy.textAllowed('', category: entry.group),
        )
        .toList();
  }

  Future<BookSource> _active(Book book) async {
    if (!bookAllowed(book)) throw const ContentBlocked();
    return _enabledSource(book.kind, book.sourceId);
  }

  Future<BookSourceEntry?> sourceEntry(BookKind kind, String id) async {
    await _builtins;
    if (await _blocked(id)) return null;
    final entry = await store.source(_verifiedSources[id], id);
    if (entry == null ||
        entry.source.kind != kind ||
        !sourceAllowed(entry.source) ||
        !policy.textAllowed('', category: entry.group)) {
      return null;
    }
    return entry;
  }

  Future<BookSource> _enabledSource(BookKind kind, String id) async {
    await _builtins;
    if (await _blocked(id)) throw const ContentBlocked();
    final entry = await store.source(_verifiedSources[id], id);
    if (entry == null || !entry.enabled || entry.source.kind != kind) {
      throw const FormatException('请先启用该来源');
    }
    if (!sourceAllowed(entry.source) ||
        !policy.textAllowed('', category: entry.group)) {
      throw const ContentBlocked();
    }
    return entry.source;
  }

  Future<List<LegadoCategory>> categories(
    BookKind kind,
    String sourceId,
    CancellationToken token,
  ) async {
    final source = await _enabledSource(kind, sourceId);
    final categories = await client.categories(source, token);
    token.check();
    if (!sourceAllowed(source)) throw const ContentBlocked();
    return categories
        .where((category) => policy.textAllowed(category.title))
        .toList();
  }

  Future<BookDiscoveryPage> discover(
    BookKind kind,
    String sourceId,
    CancellationToken token, {
    LegadoCategory? category,
    int page = 1,
    String? cursor,
  }) async {
    final source = await _enabledSource(kind, sourceId);
    final result = await client.discover(
      source,
      token,
      category: category,
      page: page,
      cursor: cursor,
    );
    if (!sourceAllowed(source) || await _blocked(sourceId)) {
      throw const ContentBlocked();
    }
    token.check();
    return (books: result.books.where(bookAllowed).toList(), next: result.next);
  }

  Future<void> restoreDefaultSources(BookKind kind) async {
    policy.supervision.require(SensitiveOperation.channels);
    final builtins = (await _builtins).where((s) => s.kind == kind).toList();
    final blocked = await store.blockedSources();
    final existing = await store.sources(await _builtins);
    await store.db.atomic(() async {
      for (final entry in existing.where((e) => e.source.kind == kind)) {
        await store.saveSource(entry.source, {'enabled': false});
      }
      for (final source in builtins) {
        if (blocked.containsKey(source.id) || !sourceAllowed(source)) continue;
        final key = 'books_source:${source.id}';
        final old = await store.read(key);
        await store.write(key, {
          if (old is Map) ...old,
          'enabled': true,
          'removed': false,
        });
      }
    }, tables: {'app_meta'});
  }

  Future<void> saveSource(
    BookSource source,
    Map<String, Object?> updates,
  ) async {
    policy.supervision.require(SensitiveOperation.channels);
    if (!sourceAllowed(source)) throw const ContentBlocked();
    await store.db.atomic(() async {
      if (await _blocked(source.id)) throw const ContentBlocked();
      await store.saveSource(source, updates);
    }, tables: {'app_meta'});
  }

  Future<void> setSourcesEnabled(
    BookKind kind,
    Set<String> ids,
    bool enabled,
  ) async {
    policy.supervision.require(SensitiveOperation.channels);
    await store.db.atomic(() async {
      final eligible = (await sources(kind)).where(
        (entry) => ids.contains(entry.source.id) && entry.enabled != enabled,
      );
      policy.supervision.require(SensitiveOperation.channels);
      await store.setSourcesEnabled(
        eligible.map((entry) => entry.source.id).toSet(),
        enabled,
      );
    }, tables: {'app_meta'});
  }

  Future<void> blockSource(BookSource source) => store.db.atomic(() async {
    policy.supervision.require(SensitiveOperation.channels);
    if (!sourceAllowed(source)) throw const ContentBlocked();
    final blocked = await store.blockedSources();
    await store.write('books_source_blacklist', {
      ...blocked,
      source.id: '${source.name} · ${source.endpoint.host}',
    });
    final aliases = await store.read('books_source_blacklist_aliases');
    await store.write('books_source_blacklist_aliases', {
      if (aliases is Map) ...aliases,
      _blacklistAlias(source): source.id,
    });
    await store.saveSource(source, {'enabled': false});
  }, tables: {'app_meta'});

  Future<bool> _blocked(String id) async =>
      (await store.blockedSources()).containsKey(id);

  String _blacklistAlias(BookSource source) {
    final host = source.endpoint.host.replaceFirst(RegExp(r'^www\.'), '');
    final path = source.endpoint.path == '/' ? '' : source.endpoint.path;
    return '${source.kind.name}:$host$path?${source.endpoint.query}:${source.sourceKey}';
  }

  Future<void> unblockSource(String id) => store.db.atomic(() async {
    policy.supervision.require(SensitiveOperation.channels);
    final blocked = await store.blockedSources()
      ..remove(id);
    await store.write('books_source_blacklist', blocked);
    final aliases = await store.read('books_source_blacklist_aliases');
    if (aliases is Map) {
      await store.write(
        'books_source_blacklist_aliases',
        {...aliases}..removeWhere((_, sourceId) => sourceId == id),
      );
    }
  }, tables: {'app_meta'});

  void _requireSubscriptionAccess() {
    policy.supervision.require(SensitiveOperation.channels);
    if (policy.supervision.enabled || policy.supervision.corrupted) {
      throw const ContentBlocked();
    }
  }

  Future<({BookSourceImport parsed, BookImportChanges changes})> subscribe(
    String address,
    CancellationToken token,
  ) async {
    _requireSubscriptionAccess();
    final uri = bookSourceLink(address);
    final id = bookSubscriptionId(uri);
    if (!_refreshingSubscriptions.add(id)) {
      throw const FormatException('此订阅正在刷新');
    }
    try {
      final input = await BookSourceDocuments(client.network, (host) {
        _requireSubscriptionAccess();
        return policy.textAllowed(host) &&
            !(policy.filterAdult && knownAdultHost(host));
      }).load(uri, token);
      token.check();
      final parsed = await parseBookSourcesOffThread(input);
      token.check();
      if (parsed.sources.isEmpty) {
        throw FormatException('没有可导入来源${parsed.issueSummary}');
      }
      final changes = await importSources(
        parsed.sources,
        subscription: uri,
        token: token,
      );
      return (parsed: parsed, changes: changes);
    } finally {
      _refreshingSubscriptions.remove(id);
    }
  }

  Future<List<BookSourceSubscription>> subscriptions() async {
    if (policy.supervision.enabled || policy.supervision.corrupted) return [];
    return (await store.subscriptions())
        .where(
          (entry) =>
              policy.textAllowed(entry.url.host) &&
              !(policy.filterAdult && knownAdultHost(entry.url.host)),
        )
        .toList();
  }

  Future<({BookSourceImport parsed, BookImportChanges changes})> importCatalog(
    AoaoStarBookCatalog catalog,
    CancellationToken token, {
    String? packId,
  }) async {
    _requireSubscriptionAccess();
    token.check();
    final parsed = await catalog.read(packId: packId);
    token.check();
    final changes = await importSources(
      parsed.sources,
      fromCatalog: true,
      token: token,
    );
    return (parsed: parsed, changes: changes);
  }

  Future<void> removeSubscription(BookSourceSubscription entry) async {
    _requireSubscriptionAccess();
    if (_refreshingSubscriptions.contains(entry.id)) {
      throw const FormatException('请先完成订阅刷新');
    }
    await store.deleteSubscription(entry);
  }

  Future<BookImportChanges> importSources(
    List<BookSource> incoming, {
    Uri? subscription,
    CancellationToken? token,
    bool fromCatalog = false,
    String? catalogRevision,
  }) async {
    policy.supervision.require(SensitiveOperation.channels);
    final builtins = await _builtins;
    final subscriptionId = subscription == null
        ? null
        : bookSubscriptionId(subscription);
    var added = 0;
    var updated = 0;
    var duplicates = 0;
    var skipped = 0;
    await store.db.atomic(() async {
      final current = await store.sources(builtins);
      final existing = {for (final entry in current) entry.source.id: entry};
      final blocked = await store.blockedSources();
      final aliases = await store.blockedAliases();
      final seen = <String>{};
      final customCount = current
          .where((entry) => !entry.source.builtin && !entry.fromCatalog)
          .length;
      final pending = <({BookSource source, BookSourceEntry? previous})>[];
      Future<void> flush() async {
        await store.writeImported(
          pending,
          subscriptionId: subscriptionId,
          fromCatalog: fromCatalog,
        );
        pending.clear();
      }

      for (final candidate in incoming) {
        token?.check();
        policy.supervision.require(SensitiveOperation.channels);
        if (subscription != null || fromCatalog) _requireSubscriptionAccess();
        final source = _keepLegacyKey(candidate, existing);
        if (aliases.contains(_blacklistAlias(candidate)) ||
            blocked.containsKey(candidate.id) ||
            blocked.containsKey(source.id) ||
            !sourceAllowed(source)) {
          skipped++;
          continue;
        }
        if (!seen.add(source.id)) {
          duplicates++;
          continue;
        }
        final previous = existing[source.id];
        if (previous != null) {
          final owned =
              subscriptionId != null &&
              previous.subscriptionId == subscriptionId;
          final newerCatalog =
              fromCatalog &&
              previous.fromCatalog &&
              source.updatedAt > previous.source.updatedAt;
          if (!previous.source.builtin &&
              (owned || newerCatalog) &&
              jsonEncode(source.toJson()) !=
                  jsonEncode(previous.source.toJson())) {
            pending.add((source: source, previous: previous));
            updated++;
          } else {
            duplicates++;
          }
        } else if (!fromCatalog && customCount + added >= 12000) {
          skipped++;
        } else {
          pending.add((source: source, previous: null));
          added++;
        }
        if (pending.length >= 128) await flush();
      }
      if (pending.isNotEmpty) await flush();
      token?.check();
      if (subscription != null || fromCatalog) _requireSubscriptionAccess();
      if (catalogRevision != null) {
        await store.write('books_catalog_revision', catalogRevision);
      }
      await _recordSubscription(subscription, added + updated + duplicates);
    }, tables: {'app_meta'});
    return (
      added: added,
      updated: updated,
      duplicates: duplicates,
      skipped: skipped,
    );
  }

  Future<void> _recordSubscription(Uri? address, int count) async {
    if (address == null || count == 0) return;
    _requireSubscriptionAccess();
    await store.saveSubscription(
      BookSourceSubscription(
        address,
        count,
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  BookSource _keepLegacyKey(
    BookSource source,
    Map<String, BookSourceEntry> existing,
  ) {
    if (source.sourceKey.isEmpty ||
        source.sourceKey.contains('#') ||
        source.sourceKey.startsWith('alias:') ||
        existing.containsKey(source.id)) {
      return source;
    }
    final legacy = existing[source.legacyId]?.source;
    if (legacy == null ||
        legacy.builtin ||
        legacy.legado == null ||
        legacy.endpoint != source.endpoint) {
      return source;
    }
    return BookSource.fromJson(source.toJson()..remove('sourceKey'));
  }

  Future<void> removeSource(BookSource source) async {
    policy.supervision.require(SensitiveOperation.channels);
    if (!sourceAllowed(source)) throw const ContentBlocked();
    await store.deleteSource(source);
  }

  Future<void> probe(
    BookSource source,
    String query,
    CancellationToken token,
  ) async {
    policy.supervision.require(SensitiveOperation.channels);
    if (!sourceAllowed(source) || await _blocked(source.id)) {
      throw const ContentBlocked();
    }
    final watch = Stopwatch()..start();
    var status = '';
    var stage = '搜索';
    try {
      final books = await client.books(
        source,
        query,
        token,
        bookAddress: _bookAddress(query),
      );
      final book = books.where(bookAllowed).firstOrNull;
      if (book == null) throw const FormatException('没有匹配作品，试试该源中已知的书名');
      stage = '详情';
      final details = await client.details(source, book, token);
      if (!bookAllowed(details)) throw const ContentBlocked();
      stage = '目录';
      final chapters = await client.chapters(source, details, token);
      final chapter = chapters
          .where((c) => policy.textAllowed(c.title))
          .firstOrNull;
      if (chapter == null) throw const FormatException('目录没有可用章节');
      stage = source.kind == BookKind.text ? '正文' : '音频';
      if (source.kind == BookKind.text) {
        final body = await client.text(source, chapter, token, book: book);
        if (body.trim().length < 40 || !policy.textAllowed(body)) {
          throw const FormatException('正文为空、过短或被内容策略拦截');
        }
      } else {
        final (uri, bytes) = await client.sampleAudio(
          source,
          chapter,
          token,
          book: book,
        );
        audiobookExtension(
          bytes,
          isM4b: uri.path.toLowerCase().endsWith('.m4b'),
        );
      }
      status = '可用 · ${watch.elapsedMilliseconds} ms';
    } on FormatException catch (error) {
      status = '$stage · ${error.message}';
    } on RemoteFailure catch (error) {
      status = '$stage · ${error.message}';
    } on Exception {
      status = '$stage · 检测失败';
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
    String? sourceId,
    LegadoCategory? category,
    int page = 1,
    int? maxSources,
    Set<String>? sourceIds,
    String? preferredSource,
    String? excludedSource,
    bool skipQidian = false,
    bool favorites = false,
    BookSearchField field = BookSearchField.all,
    void Function(BookSearchUpdate)? onProgress,
  }) async {
    if (!kindAllowed(kind)) throw const ContentBlocked();
    if (query.isNotEmpty && !policy.textAllowed(query)) {
      throw const ContentBlocked();
    }
    final address = _bookAddress(query);
    final entries = (await sources(kind, enabledOnly: true)).where((entry) {
      if (!entry.enabled ||
          (skipQidian && isQidianHost(entry.source.endpoint.host)) ||
          entry.source.id == excludedSource ||
          (sourceId != null && sourceId != entry.source.id) ||
          (sourceIds != null && !sourceIds.contains(entry.source.id))) {
        return false;
      }
      if (address != null) return entry.source.acceptsBookAddress(address);
      return entry.source.hasDiscovery ||
          (query.isNotEmpty && entry.source.hasSearch);
    }).toList();
    final prioritized = _prioritize(entries, preferredSource, favorites);
    final selected = maxSources == null
        ? prioritized
        : prioritized.take(maxSources).toList();
    token.check();
    onProgress?.call((
      sourceId: null,
      books: [],
      completed: 0,
      total: selected.length,
      failed: false,
      latencyMs: null,
    ));
    return _searchSources(
      selected,
      query,
      token,
      category,
      page,
      address,
      field,
      onProgress,
    );
  }

  List<BookSourceEntry> _prioritize(
    Iterable<BookSourceEntry> entries,
    String? preferredSource,
    bool favorites,
  ) => [
    ...entries.where(
      (entry) =>
          entry.source.id == preferredSource && (!favorites || entry.favorite),
    ),
    ...entries.where(
      (entry) => entry.source.id != preferredSource && entry.favorite,
    ),
    if (!favorites)
      ...entries.where(
        (entry) => entry.source.id != preferredSource && !entry.favorite,
      ),
  ];

  Future<({List<Book> books, int failed})> _searchSources(
    List<BookSourceEntry> selected,
    String query,
    CancellationToken token,
    LegadoCategory? category,
    int page,
    Uri? address,
    BookSearchField field,
    void Function(BookSearchUpdate)? onProgress,
  ) async {
    final results = <String, List<Book>>{};
    final match = address == null && query.trim().isNotEmpty
        ? BookSearchQuery(query, field)
        : null;
    var failed = 0;
    var cursor = 0, completed = 0;
    Future<void> fetchSources() async {
      while (cursor < selected.length) {
        token.check();
        final source = selected[cursor++].source;
        var books = <Book>[];
        var failure = false;
        int? latencyMs;
        try {
          if (sourceAllowed(source) && !await _blocked(source.id)) {
            final watch = Stopwatch()..start();
            final found = await client.books(
              source,
              query,
              token,
              category: category,
              page: page,
              bookAddress: address,
            );
            latencyMs = watch.elapsedMilliseconds;
            if (sourceAllowed(source) && !await _blocked(source.id)) {
              final allowEpisodeMatches =
                  source.kind == BookKind.audio &&
                  source.format == BookFormat.feed &&
                  field == BookSearchField.all;
              books = found
                  .where(
                    (book) =>
                        bookAllowed(book) &&
                        (match == null ||
                            allowEpisodeMatches ||
                            match.rank(book) != null),
                  )
                  .toList();
            }
          }
        } on Exception {
          failed++;
          failure = true;
        }
        token.check();
        results[source.id] = books;
        onProgress?.call((
          sourceId: source.id,
          books: books,
          completed: ++completed,
          total: selected.length,
          failed: failure,
          latencyMs: latencyMs,
        ));
      }
    }

    await Future.wait(
      List.generate(math.min(4, selected.length), (_) => fetchSources()),
    );
    token.check();
    return (
      books: selected
          .expand((entry) => results[entry.source.id] ?? const <Book>[])
          .where(bookAllowed)
          .toList(),
      failed: failed,
    );
  }

  Future<List<BookChapter>> chapters(
    Book book,
    CancellationToken token, {
    bool refresh = false,
  }) async {
    if (!bookAllowed(book) || await _blocked(book.sourceId)) {
      throw const ContentBlocked();
    }
    token.check();
    final saved = await store.entry(book);
    token.check();
    if (!bookAllowed(book) || await _blocked(book.sourceId)) {
      throw const ContentBlocked();
    }
    token.check();
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
    if (!sourceAllowed(source) ||
        !bookAllowed(book) ||
        await _blocked(book.sourceId)) {
      throw const ContentBlocked();
    }
    token.check();
    return chapters;
  }

  Future<Book> details(Book book, CancellationToken token) async {
    token.check();
    if (!bookAllowed(book)) throw const ContentBlocked();
    if (book.sourceId == 'local') return book;
    final source = await _active(book);
    final result = await client.details(source, book, token);
    token.check();
    if (!sourceAllowed(source) ||
        !bookAllowed(result) ||
        await _blocked(book.sourceId)) {
      throw const ContentBlocked();
    }
    token.check();
    return result;
  }

  Future<void> checkFollowing(BookKind kind, CancellationToken token) async {
    final entries = (await store.shelf()).where(
      (entry) =>
          entry.following && entry.book.kind == kind && bookAllowed(entry.book),
    );
    for (final entry in entries) {
      token.check();
      try {
        final fresh = await chapters(entry.book, token, refresh: true);
        token.check();
        if (fresh.isEmpty || !bookAllowed(entry.book)) continue;
        await store.updateFollowedChapters(entry.book, fresh);
      } on Exception {
        token.check();
      }
    }
  }

  Future<List<BookEdition>> alternatives(
    Book book,
    CancellationToken token,
  ) async {
    final title = bookIdentity(book.title);
    final author = bookIdentity(book.author);
    if (author.isEmpty) return [];
    final results = await find(
      book.kind,
      book.title,
      token,
      field: BookSearchField.title,
      excludedSource: book.sourceId,
    );
    final candidates = results.books
        .where(
          (other) =>
              other.sourceId != book.sourceId &&
              bookIdentity(other.title) == title &&
              bookIdentity(other.author) == author,
        )
        .toList();
    final editions = List<BookEdition?>.filled(candidates.length, null);
    var cursor = 0;
    Future<void> loadCatalogs() async {
      while (cursor < candidates.length) {
        token.check();
        final index = cursor++;
        final candidate = candidates[index];
        try {
          final catalog = await chapters(candidate, token);
          token.check();
          if (catalog.isNotEmpty) {
            editions[index] = (book: candidate, chapters: catalog);
          }
        } on Exception {
          token.check();
        }
      }
    }

    await Future.wait(
      List.generate(math.min(3, candidates.length), (_) => loadCatalogs()),
    );
    token.check();
    return editions.whereType<BookEdition>().toList();
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
    if (await _blocked(book.sourceId)) throw const ContentBlocked();
    var body = await store.text(book, chapter);
    if (body == null) {
      final source = await _active(book);
      body = await client.text(source, chapter, token, book: book);
      if (!sourceAllowed(source)) throw const ContentBlocked();
    }
    token.check();
    if (await _blocked(book.sourceId)) throw const ContentBlocked();
    token.check();
    requireBook(book, chapter);
    if (!policy.textAllowed(body)) throw const ContentBlocked();
    if (body.trim().isEmpty) throw const FormatException('章节正文为空');
    return body;
  }

  /// A failed chapter can only fall back to an unambiguous same-author edition.
  Future<({String text, Book sourceBook})> readWithFallback(
    Book book,
    BookChapter chapter,
    CancellationToken token, {
    bool automatic = true,
  }) async {
    try {
      return (text: await readText(book, chapter, token), sourceBook: book);
    } on ContentBlocked {
      rethrow;
    } on Exception {
      token.check();
      requireBook(book, chapter);
      if (!automatic || book.sourceId == 'local') rethrow;
      for (final edition in await alternatives(book, token)) {
        final match = matchingChapter(edition.chapters, chapter);
        if (match == null) continue;
        final String text;
        try {
          text = await readText(edition.book, match, token);
        } on Exception {
          token.check();
          continue;
        }
        if (await _blocked(book.sourceId)) throw const ContentBlocked();
        token.check();
        requireBook(book, chapter);
        return (text: text, sourceBook: edition.book);
      }
      rethrow;
    }
  }

  Future<List<int>> coverBytes(Book book, CancellationToken token) async {
    if (book.sourceId == qidianRecommendationId) {
      return qidian.cover(book, token);
    }
    final source = await _active(book);
    final uri = source.resolve(book.uri, book.cover, media: true);
    final document = await client.fetch(
      source,
      uri,
      token,
      media: true,
      maxBytes: 2 * 1024 * 1024,
    );
    token.check();
    if (!sourceAllowed(source) ||
        !bookAllowed(book) ||
        await _blocked(book.sourceId)) {
      throw const ContentBlocked();
    }
    token.check();
    return document.bytes;
  }

  Future<void> download(
    Book book,
    BookChapter chapter,
    CancellationToken token, {
    List<BookEdition> alternatives = const [],
    bool tryOriginal = true,
  }) async {
    requireBook(book, chapter);
    if (await _blocked(book.sourceId)) throw const ContentBlocked();
    final candidates = [if (tryOriginal) (book, chapter)];
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
          await store.db.atomic(() async {
            if (await _blocked(book.sourceId) ||
                await _blocked(candidate.sourceId)) {
              throw const ContentBlocked();
            }
            token.check();
            requireBook(book, chapter);
            requireBook(candidate, part);
            if (!policy.textAllowed(body)) throw const ContentBlocked();
            await store.saveText(book, chapter, body);
            token.check();
          }, tables: {'app_meta'});
        } else {
          final source = await _active(candidate);
          await audioFiles.download(source, book, part, token, () {
            requireBook(book, chapter);
            requireBook(candidate, part);
            if (!sourceAllowed(source)) throw const ContentBlocked();
          }, targetChapter: chapter);
        }
        return;
      } on ContentBlocked {
        rethrow;
      } on Exception catch (error) {
        last = error;
      }
    }
    token.check();
    throw last ?? const FormatException('没有可用章节');
  }

  Future<Book> importLocal(File file) async {
    final name = p.basename(file.path);
    final extension = p.extension(name).toLowerCase();
    if (!{'.txt', '.epub', '.pdf'}.contains(extension)) {
      throw const FormatException('仅支持 TXT、EPUB 和 PDF');
    }
    if (policy.supervision.enabled || !kindAllowed(BookKind.text)) {
      throw const ContentBlocked();
    }
    final bytes = await readLocalBookBytes(file);
    final parsed = switch (extension) {
      '.epub' => await parseEpubBookOffThread(name, bytes),
      '.pdf' => await parsePdfBook(name, bytes),
      _ => await parseTextBookOffThread(name, bytes),
    };
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
    void authorize() {
      if (!bookAllowed(book) ||
          parsed.sections.any(
            (section) =>
                !policy.textAllowed(section.title) ||
                !policy.textAllowed(section.text),
          )) {
        throw const ContentBlocked();
      }
    }

    authorize();
    final contents = {
      for (final (index, section) in parsed.sections.indexed)
        BookChapter(section.title, book.uri.replace(fragment: '$index')):
            section.text,
    };
    await _saveLocalImport(
      book,
      contents,
      authorize,
      file: extension == '.txt'
          ? null
          : documentFile(book, extension.substring(1)),
      bytes: bytes,
    );
    return book;
  }

  Future<void> _saveLocalImport(
    Book book,
    Map<BookChapter, String> contents,
    void Function() authorize, {
    required File? file,
    required List<int> bytes,
  }) async {
    Directory? staging;
    try {
      if (file != null) {
        await documents.create(recursive: true);
        staging = await documents.createTemp('.pending-');
        await File(
          p.join(staging.path, 'document'),
        ).writeAsBytes(bytes, flush: true);
      }
      await store.db.atomic(() async {
        authorize();
        await store.saveTexts(book, contents);
        await store.saveBook(
          book,
          chapters: contents.keys.toList(),
          favorite: true,
        );
        if (file != null) {
          await File(p.join(staging!.path, 'document')).rename(file.path);
        }
      }, tables: {'app_meta'});
    } finally {
      if (staging != null) {
        try {
          final pending = File(p.join(staging.path, 'document'));
          if (await pending.exists()) await pending.delete();
          await staging.delete();
        } on FileSystemException {
          // A failed cleanup must not mask the outcome of the import.
        }
      }
    }
  }

  Future<void> removeLocalBook(Book book) => store.db.atomic(() async {
    await store.removeLocal(book);
    for (final extension in ['epub', 'pdf']) {
      final file = documentFile(book, extension);
      if (await file.exists()) await file.delete();
    }
  }, tables: {'app_meta'});

  Future<void> close() async {
    _http.close();
    await audioFiles.close();
  }
}
