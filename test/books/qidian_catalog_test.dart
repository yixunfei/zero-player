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
  _mobileParsing();
}

void _mobileParsing() {
  _mobileCategory();
  _mobileRank();
  _mobileHome();
  _mobileWork();
}

void _mobileCategory() {
  test('mobile category API maps records to desktop works and paginates', () {
    final desktop = Uri.parse(
      'https://www.qidian.com/all?chanId=21&subCateId=8&siteid=1&page=1',
    );
    final page = parseQidianMobileApi(
      desktop,
      jsonEncode({
        'code': 0,
        'data': {
          'total': 10000,
          'isLast': 0,
          'pageNum': 1,
          'pageMax': 50,
          'pageSize': 20,
          'records': [
            {
              'bid': 1040765595,
              'bName': '夜无疆',
              'bAuth': '辰东',
              'cnt': '429.93万字',
              'cat': '玄幻',
              'subCat': '东方玄幻',
              'state': '连载',
              'desc': '简介',
            },
            {
              'bid': '1033014772',
              'bName': '青山',
              'bAuth': '会说话的肘子',
              'cnt': '281.78万字',
              'cat': '玄幻',
            },
          ],
        },
      }),
    );
    expect(page.books.length, 2);
    final work = page.books.first;
    expect(work.sourceId, qidianRecommendationId);
    expect(work.uri.toString(), 'https://www.qidian.com/book/1040765595/');
    expect(work.cover, 'https://bookcover.yuewen.com/qdbimg/3/1040765595/180');
    expect(work.wordCount, '429.93万字');
    expect(work.category, '玄幻 · 东方玄幻');
    expect(
      page.next.toString(),
      'https://www.qidian.com/all?chanId=21&subCateId=8&siteid=1&page=2',
    );
    final last = parseQidianMobileApi(
      desktop,
      jsonEncode({
        'code': 0,
        'data': {
          'isLast': 1,
          'pageNum': 50,
          'pageMax': 50,
          'records': [
            {'bid': '1', 'bName': '样本', 'bAuth': '作者'},
          ],
        },
      }),
    );
    expect(last.next, isNull);
    expect(
      () => parseQidianMobileApi(
        desktop,
        jsonEncode({'code': 1403, 'data': null}),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

void _mobileRank() {
  test('mobile rank API keeps the rank number and desktop page cursor', () {
    final page = parseQidianMobileApi(
      Uri.parse('https://www.qidian.com/rank/yuepiao/page1/'),
      jsonEncode({
        'code': 0,
        'data': {
          'isLast': 0,
          'pageNum': 1,
          'pageMax': 50,
          'records': [
            {
              'bid': '1050460263',
              'bName': '神宠供应商',
              'bAuth': '轻泉流响',
              'cat': '轻小说',
              'subCat': '原生幻想',
              'cnt': '77.89万字',
              'rankNum': 1,
              'rankCnt': '4.19万月票',
            },
          ],
        },
      }),
    );
    expect(page.books.single.rankLabel, '1');
    expect(page.books.single.category, '轻小说 · 原生幻想');
    expect(page.next.toString(), 'https://www.qidian.com/rank/yuepiao/page2/');
  });
}

void _mobileHome() {
  test('mobile homepage aggregates featured lists and ignores ads', () {
    final page = parseQidianMobileHome(
      '<script id="vite-plugin-ssr_pageContext" type="application/json">'
      '${jsonEncode({
        'pageContext': {
          'pageProps': {
            'pageData': {
              'popNovel': [
                {'bid': 1, 'bName': '热门书', 'bAuth': '作者A'},
              ],
              'recRank': [
                {'bid': '2', 'bName': '推荐书', 'bAuth': '作者B'},
              ],
              'coverRecom': [
                {'title': '广告', 'adJumpUrl': 'https://m.qidian.com/book/9'},
              ],
            },
          },
        },
      })}</script>',
    );
    expect(page.books.map((book) => book.title), ['热门书', '推荐书']);
    expect(page.books.first.uri.toString(), 'https://www.qidian.com/book/1/');
    expect(page.next, isNull);
  });
}

void _mobileWork() {
  test('mobile work page exposes recommendations from the page context', () {
    final info = parseQidianInfo(
      '<html><head>'
      '<meta property="og:novel:update_time" content="2026-11-14 05:38:05">'
      '</head><body>'
      '<script id="vite-plugin-ssr_pageContext" type="application/json">'
      '${jsonEncode({
        'pageContext': {
          'pageProps': {
            'pageData': {
              'bookInfo': {'authorName': '辰东', 'bookStatus': '连载', 'chanName': '玄幻', 'subCateName': '东方玄幻', 'updChapterName': '第873章 改命涉因果', 'showWordsCnt': '429.93万', 'recomAll': 12758520, 'recomWeek': 70261},
            },
          },
        },
      })}</script></body></html>',
    );
    expect(info.author, '辰东');
    expect(info.status, '连载');
    expect(info.category, '玄幻 · 东方玄幻');
    expect(info.latest, '第873章 改命涉因果');
    expect(info.updated, '2026-11-14 05:38:05');
    expect(info.words, '429.93万');
    expect(info.totalRecommendations, '1275.85万');
    expect(info.weeklyRecommendations, '7.03万');
    final small = parseQidianInfo(
      '<script id="vite-plugin-ssr_pageContext" type="application/json">'
      '${jsonEncode({
        'pageContext': {
          'pageProps': {
            'pageData': {
              'bookInfo': {'authorName': '作者', 'bookName': '样本', 'recomAll': 90, 'recomWeek': 0},
            },
          },
        },
      })}</script>',
    );
    expect(small.totalRecommendations, '90');
    expect(small.weeklyRecommendations, '0');
  });

  test('work page cover replaces the list thumbnail with the hi-res rendition', () {
    String page(String head) =>
        '<html><head>$head</head><body>'
        '<script id="vite-plugin-ssr_pageContext" type="application/json">'
        '${jsonEncode({
          'pageContext': {
            'pageProps': {
              'pageData': {
                'bookInfo': {'authorName': '辰东', 'bookName': '夜无疆'},
              },
            },
          },
        })}</script></body></html>';
    const real = 'https://bookcover.yuewen.com/qdbimg/349573/1040765595/600';
    expect(
      parseQidianInfo(
        page(
          '<meta property="og:image" '
          'content="//bookcover.yuewen.com/qdbimg/349573/1040765595/180">',
        ),
      ).cover,
      real,
    );
    expect(
      parseQidianInfo(
        page(
          '<script type="application/ld+json">{"image":"$real"}</script>',
        ),
      ).cover,
      real,
    );
    expect(
      parseQidianInfo(
        page(
          '<img src="//bookcover.yuewen.com/qdbimg/349573/1040765595/180" '
          'class="detail__header-cover__img" alt="夜无疆">',
        ),
      ).cover,
      real,
    );
    expect(
      parseQidianInfo(
        page('<meta property="og:image" content="//evil.test/cover.jpg">'),
      ).cover,
      isEmpty,
    );
    expect(
      parseQidianInfo(
        '<meta property="og:novel:book_name" content="夜无疆">'
        '<meta property="og:image" '
        'content="//bookcover.yuewen.com/qdbimg/349573/1040765595/180">'
        '<div class="book-info"><h1>夜无疆</h1></div>',
      ).cover,
      real,
    );
  });
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
      expect(sections.length, greaterThan(150));
      expect(
        sections.any((s) => s.title == '东方玄幻' && s.group.contains('男生')),
        isTrue,
      );
      expect(
        sections.any((s) => s.title == '宫闱宅斗' && s.group.contains('女生')),
        isTrue,
      );
      expect(
        sections.any(
          (s) => s.title == '月票榜' && s.address == '/rank/yuepiao/page1/',
        ),
        isTrue,
      );
      expect(
        sections.any(
          (s) => s.title == '月票榜' && s.address == '/mm/rank/yuepiao/page1/',
        ),
        isTrue,
      );
      expect(
        sections.any((s) => s.title == '精选推荐' && s.address == '/'),
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
