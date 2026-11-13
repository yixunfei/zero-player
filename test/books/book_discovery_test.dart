import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/aoaostar_book_catalog.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/book_shelf_lists.dart';
import 'package:zero_player/features/books/data/legado/legado_request.dart';
import 'package:zero_player/features/books/data/legado/legado_worker.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/domain/book_search.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restore defaults disables extra sources and respects blacklist',
    () async {
      final services = await _services();
      final repo = services.books;
      await repo.ensureCatalog();
      final entries = await repo.sources(BookKind.text);
      final extra = entries.firstWhere((e) => !e.source.builtin).source;
      final builtin = entries.firstWhere((e) => e.source.builtin).source;
      await repo.saveSource(extra, {'enabled': true, 'favorite': true});
      for (final e in entries.where((e) => e.source.builtin)) {
        await repo.saveSource(e.source, {'enabled': false});
      }
      await repo.blockSource(builtin);
      await repo.restoreDefaultSources(BookKind.text);
      final restored = await repo.sources(BookKind.text);
      expect(
        restored.where((e) => !e.source.builtin).every((e) => !e.enabled),
        isTrue,
      );
      expect(restored.where((e) => e.source.builtin), isNotEmpty);
      expect(
        restored.where((e) => e.source.builtin).every((e) => e.enabled),
        isTrue,
      );
      expect(restored.any((e) => e.source.id == builtin.id), isFalse);
      expect(
        restored.firstWhere((e) => e.source.id == extra.id).favorite,
        isTrue,
      );
    },
  );
  _bundledPacks();
  _zipBackup();
  _sourceVariants();
  _retiredNews();
  _defaultImport();
  _shelf();
  _searchRelevance();
}

void _searchRelevance() {
  test('book relevance ignores synopsis and separates author from title', () {
    final uri = Uri.parse('https://books.test/book');
    final authored = Book('site', BookKind.text, '埃涅阿斯纪', '作者：[古罗马] 维吉尔', uri);
    final title = Book('site', BookKind.text, '维吉尔', '另一个作者', uri);
    final synopsis = Book(
      'site',
      BookKind.text,
      '平台推荐',
      '其他人',
      uri,
      description: '内含维吉尔',
    );
    final partial = Book('site', BookKind.text, '维·小说', '', uri);
    final query = BookSearchQuery('维吉尔', BookSearchField.all);
    expect(query.rank(title), lessThan(query.rank(authored)!));
    expect(query.rank(synopsis), isNull);
    expect(query.rank(partial), isNull);
    expect(BookSearchQuery('维吉尔', BookSearchField.author).rank(title), isNull);
    expect(BookSearchQuery('维吉尔', BookSearchField.author).rank(authored), 1);
    expect(
      BookSearchQuery('维吉尔', BookSearchField.title).rank(authored),
      isNull,
    );
    expect(bookAuthorName(authored.author), '维吉尔');
    expect(bookAuthorName('作者：[墨]'), '[墨]');
    final technical = Book('site', BookKind.text, 'Ｄａｒｔ 实战', '作者', uri);
    expect(
      BookSearchQuery('dart 实战', BookSearchField.title).rank(technical),
      0,
    );
    final cpp = Book('site', BookKind.text, 'Ｃ＋＋ 实战', '作者', uri);
    final c = Book('site', BookKind.text, 'C 实战', '作者', uri);
    final programming = BookSearchQuery('C++', BookSearchField.title);
    expect(programming.rank(cpp), isNotNull);
    expect(programming.rank(c), isNull);
  });
}

void _defaultImport() {
  test(
    'default import is idempotent and blacklist survives subsequent imports',
    () async {
      final services = await _services();
      final repository = services.books;
      await Future.wait([
        repository.ensureCatalog(),
        repository.ensureCatalog(),
      ]);
      final sources = await repository.sources(BookKind.text);
      final imported = sources.where((entry) => entry.fromCatalog).toList();
      expect(imported.length, greaterThan(1800));
      expect(imported.every((entry) => !entry.enabled), isTrue);
      final first = imported[0].source, second = imported[1].source;
      final selected = {first.id, second.id};
      await repository.setSourcesEnabled(BookKind.text, selected, true);
      expect(
        (await repository.sources(
          BookKind.text,
          enabledOnly: true,
        )).where((entry) => selected.contains(entry.source.id)),
        hasLength(2),
      );
      await repository.setSourcesEnabled(BookKind.text, selected, false);
      expect(
        (await repository.sources(
          BookKind.text,
          enabledOnly: true,
        )).where((entry) => selected.contains(entry.source.id)),
        isEmpty,
      );
      await repository.blockSource(first);
      await repository.removeSource(second);
      await repository.ensureCatalog();
      expect(
        (await repository.sources(
          BookKind.text,
        )).any((entry) => selected.contains(entry.source.id)),
        isFalse,
      );
      expect((await repository.importSources([first, second])).skipped, 1);
      expect(
        (await repository.sources(
          BookKind.text,
        )).any((entry) => entry.source.id == second.id),
        isTrue,
      );
      await repository.unblockSource(first.id);
      expect(
        (await repository.sources(
          BookKind.text,
        )).singleWhere((entry) => entry.source.id == first.id).enabled,
        isFalse,
      );
    },
  );
}

void _shelf() {
  test(
    'shelf memberships and new chapters survive reader progress saves',
    () async {
      final services = await _services();
      final store = services.books.store;
      final book = Book(
        'local',
        BookKind.text,
        '夜读',
        '',
        Uri.parse('book:night'),
      );
      final lists = BookShelfLists(store, BookKind.text);
      await lists.save('在读', ShelfListKind.group);
      await lists.save('已读', ShelfListKind.group);
      await lists.save('科幻', ShelfListKind.collection);
      await lists.save('旅行', ShelfListKind.list);
      final created = await lists.load();
      await lists.assign(book, created.map((list) => list.id).toSet());
      final assigned = (await lists.load()).where(
        (list) => list.books.contains(book.id),
      );
      expect(assigned.map((list) => list.kind), [
        ShelfListKind.group,
        ShelfListKind.collection,
        ShelfListKind.list,
      ]);
      final first = BookChapter('第一章', Uri.parse('book:night#1'));
      final second = BookChapter('第二章', Uri.parse('book:night#2'));
      await store.saveBook(
        book,
        following: true,
        chapters: [first],
        last: first,
        position: .4,
      );
      await store.updateFollowedChapters(book, [first, second]);
      await store.updateFollowedChapters(book, [first, second]);
      await store.saveBook(book, chapters: [first], last: first, position: .5);
      final entry = (await store.entry(book))!;
      expect(entry.newChapters, 1);
      expect(entry.chapters.map((chapter) => chapter.id), [
        first.id,
        second.id,
      ]);
      expect(entry.position, .5);
      await store.saveBook(book, clearUpdates: true);
      expect((await store.entry(book))!.newChapters, 0);
    },
  );
}

void _bundledPacks() {
  test('the seven offline book packs account for every published row', () async {
    final services = await _services();
    final repository = services.books;
    final catalog = await AoaoStarBookCatalog.load();
    expect(catalog.packs.map((pack) => pack.count), [
      3907,
      22,
      128,
      86,
      939,
      1554,
      2117,
    ]);
    final result = await repository.importCatalog(catalog, CancellationToken());
    final parsed = result.parsed;
    expect(parsed.sources.length + parsed.duplicates + parsed.rejected, 8753);
    expect(result.changes.added, greaterThan(1800));
    final entries = [
      ...await repository.sources(BookKind.text),
      ...await repository.sources(BookKind.audio),
    ].where((entry) => entry.fromCatalog).toList();
    expect(entries.length, result.changes.added);
    expect(
      entries.every((entry) => !entry.enabled && !entry.source.builtin),
      isTrue,
    );
    final edition = await catalog.read(packId: '71e56d4f');
    expect(edition.sources.length + edition.duplicates + edition.rejected, 22);
    final repeated = await repository.importCatalog(
      catalog,
      CancellationToken(),
      packId: '71e56d4f',
    );
    expect(repeated.changes.added + repeated.changes.updated, 0);
    final cancelled = CancellationToken()..cancel();
    await expectLater(
      repository.importCatalog(catalog, cancelled),
      throwsA(isA<RequestCancelled>()),
    );
    debugPrint(
      'Bundled catalog parsed ${parsed.sources.length} distinct sources, ${parsed.duplicates} duplicates, ${parsed.rejected} incompatible, ${result.changes.added} installed, ${result.changes.skipped} filtered. ${parsed.issues}',
    );
  });
}

void _zipBackup() {
  test(
    'Legado backups import book and RSS source files with bounded paths',
    () {
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'backup/bookSource.json',
            jsonEncode([_legado('https://books.test/')]),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'backup/rssSource.json',
            jsonEncode([
              {'sourceName': '订阅', 'sourceUrl': 'https://rss.test/feed'},
            ]),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'backup/bookshelf.json',
            'ignored private backup data',
          ),
        );
      expect(
        parseBookSourceBytes(ZipEncoder().encode(archive)).sources,
        hasLength(2),
      );
      archive.addFile(ArchiveFile.string('other/BookSource.json', '[]'));
      expect(
        () => parseBookSourceBytes(ZipEncoder().encode(archive)),
        throwsFormatException,
      );
    },
  );
}

void _sourceVariants() {
  test(
    'source variants keep their address and Legado discovery labels',
    () async {
      final parsed = parseBookSources(
        jsonEncode([
          _legado('https://books.test/'),
          _legado('http://www.books.test/'),
          _legado('https://books.test/zh/'),
          _legado('https://books.test/#mirror'),
        ]),
      );
      expect(parsed.sources.length, 3);
      expect(parsed.duplicates, 1);
      final source = BookSource.fromJson(parsed.sources.last.toJson());
      expect(source.id, parsed.sources.last.id);
      expect(source.endpoint.fragment, isEmpty);
      expect(source.hasDiscovery, isTrue);
      final categories = source.legado!.categories;
      expect(categories.map((category) => category.title), ['科幻', '古籍']);
      expect(categories.first.paginated, isTrue);
      expect(
        LegadoRequest.parse(
          source,
          source.endpoint,
          categories.first.address,
          page: 3,
        ).uri.path,
        '/fiction/3',
      );
      final direct = source.endpoint.resolve('/book/7');
      expect(source.acceptsBookAddress(direct), isTrue);
      expect(
        source.acceptsBookAddress(Uri.parse('https://elsewhere.test/book/7')),
        isFalse,
      );
      final token = CancellationToken();
      final match = await runLegadoJob(
        LegadoJob(source, direct, LegadoOperation.matchBookUrl),
        token,
      );
      expect(match.matches, isTrue);
      final parsedBook = await runLegadoJob(
        LegadoJob(
          source,
          direct,
          LegadoOperation.details,
          input: '<h1>样本书</h1><img src="/cover.jpg">',
        ),
        token,
      );
      expect(parsedBook.books.single.cover, 'https://books.test/cover.jpg');
      final searchOnly = parseBookSourceRecord({
        ..._legado('https://books.test'),
        'enabledExplore': false,
      });
      expect(searchOnly.hasDiscovery, isFalse);
      expect(searchOnly.legado!.categories.length, 2);
    },
  );
}

void _retiredNews() {
  test(
    'retired news is hidden for existing installs and blocked on import and read',
    () async {
      final services = await _services();
      final repository = services.books;
      final source = BookSource.fromJson({
        'name': '旧资讯',
        'kind': 'text',
        'format': 'feed',
        'url': 'https://rss.ithome.com/feed',
      });
      await repository.store.write('books_source:${source.id}', {
        'source': source.toJson(),
        'enabled': true,
      });
      final article = Book(
        source.id,
        BookKind.text,
        '旧文章',
        '',
        source.endpoint,
      );
      final chapter = BookChapter('文章', source.endpoint);
      await repository.store.saveText(article, chapter, '本机副本');
      expect(
        (await repository.sources(
          BookKind.text,
        )).any((entry) => entry.source.id == source.id),
        isFalse,
      );
      expect(repository.bookAllowed(article), isFalse);
      expect((await repository.importSources([source])).skipped, 1);
      await expectLater(
        repository.readText(article, chapter, CancellationToken()),
        throwsA(isA<ContentBlocked>()),
      );
      expect(await repository.store.text(article, chapter), '本机副本');
    },
  );
}

Future<AppServices> _services() async {
  final root = await Directory.systemTemp.createTemp('book-catalog-');
  final services = AppServices.scoped(root, AppDatabase.memory());
  addTearDown(() async {
    await services.close();
    await root.delete(recursive: true);
  });
  await services.settings.load();
  await services.supervision.load();
  return services;
}

Map<String, Object?> _legado(String address) => {
  'bookSourceUrl': address,
  'bookSourceName': '样本书源',
  'bookUrlPattern': r'https?://books\.test/book/\d+',
  'searchUrl': '/search?q={{key}}',
  'exploreUrl': '科幻::/fiction/{{page}}\n古籍::/classic',
  'ruleBookInfo': {'name': 'h1@text', 'coverUrl': 'img@src'},
  'ruleContent': {'content': 'p@text'},
};
