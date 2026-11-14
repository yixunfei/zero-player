import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/qidian_catalog.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_discovery_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'official categories, ranks and pagination preserve the website URLs',
    () {
      final page = parseQidianPage(Uri.https('www.qidian.com', '/all/'), '''
      <nav><a href="/rank/followReading/">追读榜</a>
      <a href="//www.qidian.com/all/chanId21-subCateId8/">东方玄幻</a></nav>
      <ul class="book-img-text"><li>
        <div class="book-img-box"><a href="/book/1040765595/">
          <img src="//bookcover.yuewen.com/qdbimg/1/150"></a></div>
        <div class="book-mid-info"><h2><a href="/book/1040765595/?track=x">样本书</a></h2>
          <p class="author"><a class="name">样本作者</a><a>玄幻</a>
          <a class="go-sub-type">东方玄幻</a><span>连载</span></p>
          <p class="update"><a href="/chapter/123/">第二章</a></p>
        </div></li>
        <li class="book-mid-info"><h2><a href="/book/1040765595/">重复</a></h2></li>
        <li class="book-mid-info"><h2><a href="//evil.test/book/123/">外部作品</a></h2></li>
      </ul>
      <a class="lbf-pagination-next" href="/all/chanId21-page2/">&gt;</a>
    ''');
      expect(page.sections.map((item) => item.title), ['追读榜', '东方玄幻']);
      expect(
        page.next.toString(),
        'https://www.qidian.com/all/chanId21-page2/',
      );
      final work = page.books.single;
      expect(work.sourceId, qidianRecommendationId);
      expect(work.uri.toString(), 'https://www.qidian.com/book/1040765595/');
      expect(work.cover, 'https://bookcover.yuewen.com/qdbimg/1/150');
      expect(work.category, '玄幻 · 东方玄幻');
      expect(work.latestChapter, '第二章');
    },
  );

  test('work fields distinguish a real zero from an unpublished count', () {
    final info = parseQidianInfo('''
      <meta property="og:novel:book_name" content="样本书">
      <meta property="og:novel:author" content="作者">
      <meta property="og:novel:status" content="连载">
      <meta property="og:novel:category" content="玄幻">
      <meta property="og:novel:latest_chapter_name" content="第一章">
      <meta property="og:novel:update_time" content="2026-11-14 06:00:00">
      <div class="book-info"><p><em>26.06万</em>字
        <em>90</em>总推荐 <em>0</em>周推荐</p></div>
    ''');
    expect(info.author, '作者');
    expect(info.status, '连载');
    expect(info.category, '玄幻');
    expect(info.latest, '第一章');
    expect(info.updated, '2026-11-14 06:00:00');
    expect(info.words, '26.06万');
    expect(info.totalRecommendations, '90');
    expect(info.weeklyRecommendations, '0');
    final missing = parseQidianInfo(
      '<div class="book-info"><h1>样本</h1><p>𘢧𘢩万字</p></div>',
    );
    expect(missing.words, isEmpty);
    expect(missing.weeklyRecommendations, isEmpty);
  });

  test('browser challenge is surfaced as a failure', () {
    expect(
      () => parseQidianPage(
        qidianHome,
        '<script src="/example/probe.js?v=1"></script>',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('浏览器验证'),
        ),
      ),
    );
  });

  _recommendationSearch();
  _cachedDiscovery();
}

void _cachedDiscovery() {
  testWidgets(
    'blocked refresh keeps the last official page and ignores expired cache',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('qidian-cache-'),
      ))!;
      final services = AppServices.scoped(root, AppDatabase.memory());
      await services.settings.load();
      await services.supervision.load();
      addTearDown(() async {
        await tester.runAsync(() async {
          await services.close();
          await root.delete(recursive: true);
        });
      });
      final repo = services.books;
      final book = Book(
        qidianRecommendationId,
        BookKind.text,
        '缓存作品',
        '作者',
        qidianHome.resolve('/book/1040765595/'),
      );
      Future<void> save(DateTime time) => repo.store.db.customStatement(
        'INSERT OR REPLACE INTO recommendation_cache VALUES(?,?,?)',
        [
          'qidian:${qidianHome.resolve('/')}',
          jsonEncode({
            'books': [
              book.toJson(),
              {
                ...book.toJson(),
                'url': 'https://example.test/book/1/',
                'title': '外部作品',
              },
            ],
            'sections': [],
          }),
          time.millisecondsSinceEpoch,
        ],
      );
      await save(DateTime.now());
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookDiscoveryView(
              repository: repo,
              kind: BookKind.text,
              sources: const [],
              active: true,
              onOpen: (book, {direct = false}) {
                expect(direct, isFalse);
                opened = book.title;
              },
              onSearch: (_, _, _) {},
              onSourceFavorite: (_, _) {},
              onManage: () {},
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 400 && find.text(book.title).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(find.text(book.title), findsWidgets);
      expect(find.textContaining('保存的书单'), findsOneWidget);
      expect(find.text('外部作品'), findsNothing);
      await tester.tap(find.text(book.title).last);
      expect(opened, book.title);
      await tester.tap(find.byTooltip('刷新当前页面'));
      await tester.pumpAndSettle();
      expect(find.text(book.title), findsWidgets);
      await save(DateTime.now().subtract(const Duration(days: 8)));
      await expectLater(
        repo.qidian.load('/', CancellationToken()),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repo.qidian.load('/', CancellationToken()..cancel()),
        throwsA(isA<RequestCancelled>()),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

void _recommendationSearch() {
  test(
    'recommendation searches only reading channels and offers both site catalogs',
    () async {
      final root = await Directory.systemTemp.createTemp('qidian-catalog-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      await services.settings.load();
      await services.supervision.load();
      final repo = services.books;
      final sections = await repo.qidian.sections;
      expect(sections.length, greaterThan(250));
      expect(
        sections.any((s) => s.title == '东方玄幻' && s.group.contains('男生')),
        isTrue,
      );
      expect(
        sections.any((s) => s.title == '宫闱宅斗' && s.group.contains('女生')),
        isTrue,
      );
      final sources = [
        for (final host in ['first.test', 'second.test', 'm.qidian.com'])
          BookSource.fromJson({
            'url': 'https://$host',
            'name': host,
            'kind': 'text',
            'format': 'featured',
            'featured': [
              {'title': '样本书', 'author': '作者', 'url': '/book/1'},
            ],
            'rules': {
              'chapters': 'a',
              'chapterTitle': '@text',
              'chapterUrl': '@href',
              'content': 'p@text',
            },
          }),
      ];
      await repo.importSources(sources);
      for (final source in sources) {
        await repo.saveSource(source, {'enabled': true});
      }
      final result = await repo.find(
        BookKind.text,
        '样本书',
        CancellationToken(),
        sourceIds: sources.map((s) => s.id).toSet(),
        skipQidian: true,
      );
      expect(result.books.map((book) => book.uri.host).toSet(), {
        'first.test',
        'second.test',
      });
    },
  );
}
