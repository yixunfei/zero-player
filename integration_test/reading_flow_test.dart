import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/app_theme.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/aoaostar_book_catalog.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/books_repository.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/domain/legado_source.dart';
import 'package:zero_player/features/books/presentation/book_discovery_view.dart';
import 'package:zero_player/features/books/presentation/book_category_picker.dart';
import 'package:zero_player/features/books/presentation/book_detail_page.dart';
import 'package:zero_player/features/books/presentation/book_search_page.dart';
import 'package:zero_player/features/books/presentation/books_page.dart';
import 'package:zero_player/features/books/presentation/reader_pagination.dart';
import 'package:zero_player/features/books/presentation/reader_style.dart';
import 'package:zero_player/features/books/presentation/book_reader_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'channel shelves, offline reading and a curl across chapters',
    _readingFlow,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  testWidgets(
    'bundled rules expose named dynamic categories with QuickJS',
    (tester) =>
        _withServices((services) => _dynamicDiscovery(services, tester)),
  );
  testWidgets(
    'original bundled Gulong source lists books, chapters and text',
    (tester) => _withServices((services) => _originalSource(services, tester)),
    skip: !const bool.fromEnvironment('RUN_AOAOSTAR_ONLINE'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
  testWidgets(
    'Sudugu category, next page, ranked metadata, directory and text',
    (tester) => _withServices((services) => _sudugu(services, tester)),
    skip: !const bool.fromEnvironment('RUN_NOVELS_ONLINE'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
  testWidgets(
    'long directory navigation stays available and restores current chapter',
    (tester) => _withServices((services) => _longDirectory(services, tester)),
  );
}

Future<void> _sudugu(AppServices services, WidgetTester tester) async {
  final repo = services.books;
  final entry = (await repo.sources(
    BookKind.text,
  )).singleWhere((entry) => entry.source.name == '速读谷');
  final token = CancellationToken();
  final categories = await repo.categories(
    BookKind.text,
    entry.source.id,
    token,
  );
  final fantasy = categories.singleWhere((category) => category.title == '玄幻');
  final ranking = categories.singleWhere((category) => category.title == '排行榜');
  final first = await repo.discover(
    BookKind.text,
    entry.source.id,
    token,
    category: fantasy,
  );
  expect(first.books.length, greaterThan(8));
  expect(Uri.parse(first.next!).path, '/xuanhuan/2.html');
  final second = await repo.discover(
    BookKind.text,
    entry.source.id,
    token,
    category: fantasy,
    page: 2,
    cursor: first.next,
  );
  expect(
    second.books.any((book) => !first.books.any((old) => book.id == old.id)),
    isTrue,
  );
  final ranked = await repo.discover(
    BookKind.text,
    entry.source.id,
    token,
    category: ranking,
  );
  expect(ranked.books.first.rankLabel, isNotEmpty);
  expect(Uri.parse(ranked.next!).path, '/paihang/2.html');
  final details = await repo.details(ranked.books.first, token);
  expect(details.wordCount, isNotEmpty);
  expect(details.updatedLabel, isNotEmpty);
  final chapters = await repo.chapters(details, token);
  expect(chapters.length, greaterThan(10));
  final body = await repo.readText(details, chapters.first, token);
  expect(body.length, greaterThan(100));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BookDiscoveryView(
          repository: repo,
          kind: BookKind.text,
          sources: [entry],
          active: true,
          onOpen: (_, {direct = false}) {},
          onSearch: (_, _, _) {},
          onSourceFavorite: (_, _) {},
          onManage: () {},
        ),
      ),
    ),
  );
  await tester.tap(find.widgetWithText(OutlinedButton, '精选推荐'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry.source.name).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('排行榜'));
  await _waitFor(
    tester,
    () => find.text(ranked.books.first.title).evaluate().isNotEmpty,
  );
  final feed = find.byType(CustomScrollView);
  final controller = tester.widget<CustomScrollView>(feed).controller!;
  final initialExtent = controller.position.maxScrollExtent;
  controller.jumpTo(initialExtent);
  await _waitFor(
    tester,
    () => controller.position.maxScrollExtent > initialExtent + 100,
  );
  expect(controller.offset, closeTo(initialExtent, 4));
  await tester.pumpWidget(const SizedBox());
  await repo.store.saveText(details, chapters.first, body);
  await repo.store.saveBook(
    details,
    chapters: chapters,
    last: chapters[1],
    position: .3,
  );
  await _checkDownload(tester, services, details, chapters);
}

Future<void> _longDirectory(AppServices services, WidgetTester tester) async {
  final book = Book(
    'local',
    BookKind.text,
    '长目录样本',
    '',
    Uri.parse('book:long'),
  );
  final chapters = [
    for (var i = 1; i <= 900; i++)
      BookChapter('测试章节 $i', Uri.parse('book:long#$i')),
  ];
  await services.books.store.saveBook(
    book,
    chapters: chapters,
    last: chapters[734],
  );
  await tester.pumpWidget(
    MaterialApp(
      home: BookDetailPage(services: services, initial: book),
    ),
  );
  await _waitFor(tester, () => find.byTooltip('章节导航').evaluate().isNotEmpty);
  await tester.tap(find.byTooltip('章节导航'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('定位当前章节'));
  await tester.pumpAndSettle();
  final current = find.widgetWithText(ListTile, chapters[734].title);
  expect(current.hitTestable(), findsOneWidget);
  expect(tester.widget<ListTile>(current).selected, isTrue);
  await tester.tap(find.byTooltip('章节导航'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('目录回顶'));
  await tester.pumpAndSettle();
  final scroll = tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!;
  expect(scroll.offset, 0);
  await tester.pumpWidget(const SizedBox());
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 240 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue);
}

Future<void> _readingFlow(WidgetTester tester) => _withServices((
  services,
) async {
  final key = GlobalKey();
  final repository = services.books;
  try {
    for (final entry in await repository.sources(BookKind.text)) {
      await repository.saveSource(entry.source, {'enabled': false});
    }
    final first = _featured('青松书库', 'first.test', [
      '云中札记',
      '时间的河流',
      '静水深处',
      '晨光书简',
      '落叶与微风',
    ]);
    final second = _featured(
      '云边书局',
      'second.test',
      ['漫长的午后', '云中札记', '越过海岸', '窗边的远山', '迷雾中的回声'],
      authors: {'漫长的午后': '作者：[古罗马] 维吉尔', '迷雾中的回声': '维吉尔'},
    );
    await repository.importSources([first, second]);
    await repository.saveSource(first, {'enabled': true, 'favorite': true});
    await repository.saveSource(second, {'enabled': true});
    final text = List.filled(
      36,
      '海面上吹来缓慢而温柔的风。两盏小灯在暗处依次亮起，照见了海图上熟悉的航线。',
    ).join('\n\n');
    final file = await File(
      '${services.root.path}/夜航札记.txt',
    ).writeAsString('第一章 启程\n$text\n\n潮汐时刻表\n第二章 靠岸\n灯塔亮起，船停在湾里。');
    final book = await repository.importLocal(file);
    await repository.store.write(
      'books_reader_preferences',
      const ReaderPreferences(
        mode: ReaderTurnMode.curl,
        paper: ReaderPaper.warm,
      ).toJson(),
    );
    if (Platform.isWindows) {
      await tester.binding.setSurfaceSize(const Size(1120, 760));
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            Brightness.light,
            false,
            'light',
            font: 'notoSans',
          ),
          home: Scaffold(
            body: BooksPage(services: services, kind: BookKind.text),
          ),
        ),
      ),
    );
    await _checkDiscovery(tester, key, first, second);
    expect(await repository.store.read('books_discovery_direct:text'), true);
    await _checkReader(tester, key, repository, book);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  }
});

Future<void> _checkDiscovery(
  WidgetTester tester,
  GlobalKey key,
  BookSource first,
  BookSource second,
) async {
  await tester.pumpAndSettle();
  expect(find.text('精选推荐'), findsOneWidget);
  await tester.tap(find.text('按渠道聚合'));
  await tester.pumpAndSettle();
  expect(find.text(first.name), findsOneWidget);
  await _capture(key, 'reading-discovery');
  if (Platform.isWindows) {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('聚合渠道'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(second.name).last);
  await tester.pumpAndSettle();
  expect(find.text(second.name), findsOneWidget);
  expect(find.text('漫长的午后'), findsWidgets);
  await _checkBookSearch(tester, first, second);
  expect(find.text(second.name), findsOneWidget);
  await _capture(key, 'reading-channel');
}

Future<void> _checkBookSearch(
  WidgetTester tester,
  BookSource first,
  BookSource second,
) async {
  await tester.tap(find.text('云中札记').last);
  await tester.pumpAndSettle();
  expect(find.text('聚合搜索'), findsOneWidget);
  expect(find.textContaining('2 个渠道 · 含当前渠道'), findsOneWidget);
  await tester.tap(find.widgetWithText(ListTile, '云中札记'));
  await tester.pumpAndSettle();
  expect(find.textContaining(' ms'), findsNWidgets(2));
  expect(find.textContaining('当前渠道'), findsWidgets);
  expect(
    tester.getTopLeft(find.text(second.name)).dy,
    lessThan(tester.getTopLeft(find.text(first.name)).dy),
  );
  await tester.tap(find.byTooltip('收藏渠道'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('取消收藏渠道'), findsNWidgets(2));
  await tester.tap(find.text('关闭'));
  await tester.pumpAndSettle();
  await tester.pageBack();
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), '维吉尔');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
  expect(find.byType(BookSearchPage), findsOneWidget);
  expect(find.widgetWithText(ListTile, '漫长的午后'), findsOneWidget);
  expect(find.widgetWithText(ListTile, '迷雾中的回声'), findsOneWidget);
  await tester.tap(find.widgetWithText(ChoiceChip, '书名'));
  await tester.pumpAndSettle();
  expect(find.text('没有符合条件的作品'), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();

  final sourceMenu = find.byTooltip('渠道操作');
  if (sourceMenu.evaluate().isNotEmpty) {
    await tester.tap(sourceMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('渠道书单点击方式'));
  } else {
    await tester.tap(find.byTooltip('渠道书单点击方式'));
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开当前渠道'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('漫长的午后').last);
  await tester.pumpAndSettle();
  expect(find.byType(BookDetailPage), findsOneWidget);
  expect(find.text('查找其他渠道'), findsOneWidget);
  await tester.tap(find.byTooltip('取消收藏渠道'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('收藏渠道'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, '作者：[古罗马] 维吉尔'));
  await tester.pumpAndSettle();
  expect(
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '作者')).selected,
    isTrue,
  );
  expect(find.widgetWithText(ListTile, '迷雾中的回声'), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.tap(find.text('查找其他渠道'));
  await tester.pumpAndSettle();
  expect(find.byType(BookSearchPage), findsOneWidget);
  expect(find.text('没有符合条件的作品'), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> _checkReader(
  WidgetTester tester,
  GlobalKey key,
  BooksRepository repository,
  Book book,
) async {
  await tester.tap(find.text('书架'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(book.title));
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始阅读'));
  await tester.pumpAndSettle();
  final content = find.byType(ReaderTapZones);
  expect(content, findsOneWidget);
  await _verifyReadingArea(tester, key);
  final body = tester.getRect(content);
  final viewport = tester.getRect(find.byType(ReaderViewport));
  await _capture(key, 'reading-paper');
  final gesture = await tester.startGesture(
    Offset(viewport.right - 12, viewport.center.dy),
  );
  await gesture.moveBy(const Offset(-26, 0));
  await gesture.moveBy(Offset(-viewport.width * .39, 0));
  await tester.pump();
  await _capture(key, 'reading-curl');
  await gesture.up();
  await tester.pumpAndSettle();
  expect(find.textContaining('2 /'), findsOneWidget);
  await tester.tapAt(body.center);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('章内查找'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '潮汐时刻表');
  await tester.pumpAndSettle();
  expect(find.text('1 处匹配'), findsOneWidget);
  final result = find.descendant(
    of: find.byType(ListTile),
    matching: find.textContaining('潮汐时刻表', findRichText: true),
  );
  await tester.tap(result);
  await tester.pumpAndSettle();
  await tester.drag(find.byType(ReaderViewport), Offset(-body.width * .53, 0));
  await tester.pumpAndSettle();
  final entry = (await repository.store.entry(book))!;
  expect(entry.last, entry.chapters.last.id);
  if (Platform.isAndroid) {
    final edge = MediaQuery.systemGestureInsetsOf(tester.element(content)).left;
    final size = MediaQuery.sizeOf(tester.element(content));
    final start = Offset(edge + 5, size.height / 2);
    await tester.dragFrom(start, Offset(size.width * .35, 0));
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderPage), findsNothing);
    expect(find.byType(BookDetailPage), findsOneWidget);
  }
}

Future<void> _verifyReadingArea(WidgetTester tester, GlobalKey appKey) async {
  final viewport = find.byType(ReaderViewport);
  expect(tester.getRect(viewport), tester.getRect(find.byKey(appKey)));
  if (Platform.isAndroid) {
    await tester.pump(const Duration(milliseconds: 450));
    final view = View.of(tester.element(viewport));
    expect(view.viewPadding.top, 0);
    expect(view.viewPadding.bottom, 0);
  }
}

Future<void> _dynamicDiscovery(
  AppServices services,
  WidgetTester tester,
) async {
  final repository = services.books;
  final catalog = await AoaoStarBookCatalog.load();
  final result = await repository.importCatalog(
    catalog,
    CancellationToken(),
    packId: '71e56d4f',
  );
  expect(
    result.parsed.sources.length +
        result.parsed.duplicates +
        result.parsed.rejected,
    22,
  );
  expect(result.changes.added, greaterThan(0));
  final source = parseBookSourceRecord({
    'bookSourceName': '动态分类样本',
    'bookSourceUrl': 'https://books.test',
    'exploreUrl':
        '@js:JSON.stringify([{title:"人文",url:"/human/{{page}}"}, {title:"历史",url:"/history"}])',
    'ruleContent': {'content': 'article@text'},
  });
  final categories = await repository.client.categories(
    source,
    CancellationToken(),
  );
  expect(categories.map((category) => category.title), ['人文', '历史']);
  expect(categories.first.paginated, isTrue);

  LegadoCategory? chosen;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => chosen = await showBookCategoryPicker(
              context,
              categories,
              categories.first,
            ),
            child: const Text('查看分类'),
          ),
        ),
      ),
    ),
  );
  try {
    await tester.tap(find.text('查看分类'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '人文')).selected,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), '历');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '人文'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '历史'));
    await tester.pumpAndSettle();
    expect(chosen, categories.last);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
  }
}

Future<void> _originalSource(AppServices services, WidgetTester tester) async {
  final catalog = await AoaoStarBookCatalog.load();
  final pack = await catalog.read(packId: '2a1f129b');
  final source = pack.sources.singleWhere(
    (source) => source.endpoint.host == 'www.gulongwang.com',
  );
  final token = CancellationToken();
  final client = services.books.client;
  final categories = await client.categories(source, token);
  expect(categories.single.title, '古龙全集');
  final books = await client.books(
    source,
    '',
    token,
    category: categories.single,
  );
  final book = books.firstWhere((book) => book.title.contains('苍穹神剑'));
  final chapters = await client.chapters(source, book, token);
  expect(chapters, isNotEmpty);
  final body = await client.text(source, chapters.first, token, book: book);
  expect(body.length, greaterThan(100));
  await services.books.store.saveText(book, chapters.first, body);
  expect(await services.books.readText(book, chapters.first, token), body);
  expect(chapters.length, greaterThan(2));
  await services.books.store.saveBook(
    book,
    chapters: chapters,
    last: chapters[1],
    position: .3,
  );
  await _checkDownload(tester, services, book, chapters);
}

Future<void> _checkDownload(
  WidgetTester tester,
  AppServices services,
  Book book,
  List<BookChapter> chapters,
) async {
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(services: services, initial: book),
      ),
    );
    final download = find.widgetWithText(OutlinedButton, '离线下载');
    await _waitFor(
      tester,
      () =>
          download.evaluate().isNotEmpty &&
          tester.widget<OutlinedButton>(download).onPressed != null,
    );
    expect(find.textContaining('当前进度'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('定位当前章节'));
    await tester.tap(find.byTooltip('定位当前章节'));
    await tester.pumpAndSettle();
    expect(find.text(chapters[1].title), findsWidgets);
    await tester.scrollUntilVisible(find.text('离线下载'), -200);
    await tester.ensureVisible(download);
    await tester.pumpAndSettle();
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(find.text('全本'), findsOneWidget);
    await tester.tap(find.text('指定区间'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '结束章节'), '2');
    await tester.tap(find.text('开始下载'));
    await _waitFor(tester, () => find.byTooltip('暂停下载').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('暂停下载'));
    await _waitFor(tester, () => find.text('下载已暂停').evaluate().isNotEmpty);
    expect(await services.books.store.savedText(book), {chapters.first.id});
    await tester.ensureVisible(find.text('继续下载'));
    await tester.tap(find.text('继续下载'));
    await _waitFor(tester, () => find.text('继续下载').evaluate().isEmpty);
    expect(await services.books.store.savedText(book), {
      chapters[0].id,
      chapters[1].id,
    });
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
  }
}

Future<void> _withServices(Future<void> Function(AppServices) action) async {
  final root = await Directory.systemTemp.createTemp('zero-reading-flow-');
  final services = AppServices.scoped(root, AppDatabase.memory());
  try {
    await services.settings.load();
    await services.supervision.load();
    await action(services);
  } finally {
    await services.close();
    await root.delete(recursive: true);
  }
}

Future<void> _capture(GlobalKey key, String name) async {
  const root = String.fromEnvironment('PROJECT_ROOT');
  if (!Platform.isWindows ||
      root.isEmpty ||
      !const bool.fromEnvironment('CAPTURE_READING_UI')) {
    return;
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$root/build/$name.png').writeAsBytes(png.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

BookSource _featured(
  String name,
  String host,
  List<String> titles, {
  Map<String, String> authors = const {},
}) => BookSource.fromJson({
  'name': name,
  'url': 'https://$host/',
  'kind': 'text',
  'format': 'featured',
  'group': '相同分组',
  'featured': [
    for (final (index, title) in titles.indexed)
      {
        'title': title,
        'author': authors[title] ?? '示例作者',
        'url': '/book/$index',
      },
  ],
  'rules': {
    'chapters': 'main a',
    'chapterTitle': 'text',
    'chapterUrl': 'href',
    'content': 'article@text',
  },
});
