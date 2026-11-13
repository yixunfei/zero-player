import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/features/books/presentation/books_page.dart';
import 'package:zero_player/features/books/presentation/book_detail_page.dart';
import 'package:zero_player/features/books/presentation/book_page_route.dart';
import 'package:zero_player/features/books/presentation/book_reader_page.dart';
import 'package:zero_player/features/books/presentation/public_library_page.dart';
import 'package:zero_player/features/books/presentation/publication_detail_page.dart';
import 'package:zero_player/features/books/presentation/reader_pagination.dart';
import 'package:zero_player/features/books/presentation/reader_style.dart';
import 'package:zero_player/features/books/data/public_catalog.dart';
import 'package:zero_player/features/books/domain/book.dart';
import '../../test_support/mobile_app_fixture.dart';

late MobileAppFixture fixture;
final platformCalls = <MethodCall>[];

void main() {
  setUp(() async {
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    fixture = MobileAppFixture();
    await fixture.initialize();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  _basicNavigationTests();
  _stackTests();
  _viewportAndExitTests();
  _immersiveRouteTest();
  _discoveryStateTest();
  _publicationRouteTest();
}

void _discoveryStateTest() {
  testWidgets('custom book discovery keeps scroll when switching modules', (
    tester,
  ) async {
    await tester.runAsync(() async {
      rootBundle.evict('assets/catalogs/books/verified.json');
      await rootBundle.loadString('assets/catalogs/books/verified.json');
    });
    var prepared = false;
    late BookSource source;
    final preparation = () async {
      for (final entry in await fixture.services.books.sources(BookKind.text)) {
        await fixture.services.books.saveSource(entry.source, {
          'enabled': false,
        });
      }
      source = BookSource.fromJson({
        'name': '本机测试书目',
        'url': 'https://reading-state.test/',
        'kind': 'text',
        'format': 'featured',
        'featured': [
          for (var i = 0; i < 40; i++)
            {'title': '星际航行$i', 'author': '作者', 'url': '/book/$i'},
        ],
        'rules': {
          'chapters': 'main a',
          'chapterTitle': 'text',
          'chapterUrl': 'href',
          'content': 'article@text',
        },
      });
      await fixture.services.books.importSources([source]);
      await fixture.services.books.saveSource(source, {'enabled': true});
      prepared = true;
    }();
    await fixture.waitFor(tester, () => prepared);
    await preparation;
    await fixture.pump(tester);
    final router = GoRouter.of(tester.element(find.byType(AppShell)));
    router.go('/reading');
    await fixture.waitFor(
      tester,
      () => find.text('星际航行0').evaluate().isNotEmpty,
    );
    expect(find.text('出版书目').hitTestable(), findsOneWidget);
    expect(find.text('导入 EPUB / PDF').hitTestable(), findsOneWidget);
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -550));
    await tester.pumpAndSettle();
    final offset = scroll.offset;
    expect(offset, greaterThan(100));
    fixture.services.contentPolicy.refresh();
    await fixture.settle(tester);
    expect(scroll.offset, closeTo(offset, 1));
    await fixture.services.books.store.saveSource(source, {
      'health': 'ok',
      'checkedAt': 7,
    });
    router.go('/settings');
    await fixture.settle(tester);
    router.go('/reading');
    await fixture.settle(tester);
    expect(scroll.offset, closeTo(offset, 1));
    await _discoveryControls(tester, scroll);
    await fixture.finish(tester);
  });
}

Future<void> _discoveryControls(
  WidgetTester tester,
  ScrollController scroll,
) async {
  await tester.tap(find.byTooltip('返回顶部'));
  await tester.pumpAndSettle();
  expect(scroll.offset, 0);
  await tester.tap(find.byTooltip('折叠书单，仅显示渠道'));
  await tester.pumpAndSettle();
  expect(find.text('星际航行0'), findsNothing);
  expect(find.widgetWithText(ListTile, '本机测试书目'), findsOneWidget);
  await tester.tap(find.byTooltip('展开全部书单'));
  await tester.pumpAndSettle();
  expect(find.text('星际航行0'), findsWidgets);
}

void _immersiveRouteTest() {
  testWidgets('reader covers the shell and returns to its book details', (
    tester,
  ) async {
    final book = Book(
      'local',
      BookKind.text,
      '沉浸阅读',
      '作者',
      Uri.parse('book:reader-route-fixture'),
    );
    final chapter = BookChapter('第一章 开始', book.uri.replace(fragment: '0'));
    await fixture.services.books.store.saveTexts(book, {
      chapter: '本地阅读内容。' * 500,
    });
    await fixture.services.books.store.saveBook(book, chapters: [chapter]);
    await fixture.services.books.store.write(
      'books_reader_preferences',
      const ReaderPreferences(mode: ReaderTurnMode.curl).toJson(),
    );
    await fixture.pump(tester, size: const Size(1024, 760));
    final router = GoRouter.of(tester.element(find.byType(AppShell)));
    router.go('/reading');
    await fixture.waitFor(
      tester,
      () => find.byType(BooksPage).evaluate().isNotEmpty,
    );
    Navigator.of(tester.element(find.byType(BooksPage))).push(
      BookPageRoute<void>(
        builder: (_) =>
            BookDetailPage(services: fixture.services, initial: book),
      ),
    );
    await fixture.waitFor(
      tester,
      () => find.text('开始阅读').evaluate().isNotEmpty,
    );
    await tester.ensureVisible(find.text('开始阅读'));
    await tester.tap(find.text('开始阅读'));
    await fixture.waitFor(
      tester,
      () => find.byType(BookReaderPage).evaluate().isNotEmpty,
    );
    await fixture.settle(tester);
    expect(find.byType(BookReaderPage), findsOneWidget);
    expect(find.byType(NavigationBar).hitTestable(), findsNothing);
    expect(find.byTooltip('渠道管理').hitTestable(), findsNothing);
    final viewport = tester.getRect(find.byType(ReaderViewport));
    expect(viewport, const Rect.fromLTWH(0, 0, 1024, 760));
    await tester.dragFrom(viewport.center, const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 /'), findsOneWidget);
    await tester.dragFrom(viewport.center, const Offset(380, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 /'), findsOneWidget);
    await tester.dragFrom(const Offset(8, 360), const Offset(240, 0));
    await fixture.settle(tester);
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(router.state.uri.path, '/reading');
    await _tabletBackOrder(tester);
    await fixture.finish(tester);
  });
}

Future<void> _tabletBackOrder(WidgetTester tester) async {
  await tester.tap(find.text('菜单'));
  await tester.pumpAndSettle();
  expect(find.byType(Drawer).hitTestable(), findsOneWidget);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.byType(Drawer).hitTestable(), findsNothing);
  expect(find.byType(BookDetailPage), findsOneWidget);
  await tester.dragFrom(const Offset(8, 360), const Offset(240, 0));
  await fixture.waitFor(
    tester,
    () => find.byType(BookDetailPage).evaluate().isEmpty,
  );
  expect(find.byType(BooksPage), findsOneWidget);
  expect(find.byType(Drawer).hitTestable(), findsNothing);
}

void _publicationRouteTest() {
  testWidgets('publication directory uses independent routes after scrolling', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await PublicCatalog.load();
    });
    await fixture.pump(tester, size: const Size(1024, 760));
    final router = GoRouter.of(tester.element(find.byType(AppShell)));
    router.go('/reading');
    await fixture.waitFor(
      tester,
      () => find.text('出版书目').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('出版书目'));
    final directory = find.byType(PublicLibraryPage);
    final list = find.descendant(
      of: directory,
      matching: find.byType(CustomScrollView),
    );
    await fixture.waitFor(tester, () => list.evaluate().isNotEmpty);
    final controller = tester.widget<CustomScrollView>(list).controller!;
    await tester.drag(list, const Offset(0, -570));
    await tester.pumpAndSettle();
    final offset = controller.offset;
    expect(offset, greaterThan(100));
    final entry = find
        .descendant(of: directory, matching: find.byType(ListTile))
        .hitTestable()
        .first;
    await tester.tap(entry);
    await fixture.settle(tester);
    expect(find.byType(PublicationDetailPage), findsOneWidget);
    expect(find.text('下载 EPUB 并阅读'), findsOneWidget);
    expect(find.byType(Drawer).hitTestable(), findsNothing);
    await tester.dragFrom(const Offset(8, 360), const Offset(240, 0));
    await fixture.settle(tester);
    expect(find.byType(PublicationDetailPage), findsNothing);
    expect(controller.offset, closeTo(offset, 1));
    await _expectTechnicalPublications(tester, controller);
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    expect(find.byType(BooksPage), findsOneWidget);
    expect(find.byType(Drawer).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.finish(tester);
  });
}

Future<void> _expectTechnicalPublications(
  WidgetTester tester,
  ScrollController controller,
) async {
  controller.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ChoiceChip, '技术图书'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Docker 从入门到实践'));
  await fixture.settle(tester);
  expect(find.text('应用内阅读'), findsOneWidget);
  await tester.binding.handlePopRoute();
  await fixture.settle(tester);
  expect(find.byType(PublicationDetailPage), findsNothing);
  await tester.enterText(
    find.byType(TextField),
    'The Project Gutenberg RST Manual',
  );
  await tester.pump(const Duration(milliseconds: 250));
  await fixture.settle(tester);
  await tester.tap(
    find.widgetWithText(ListTile, 'The Project Gutenberg RST Manual'),
  );
  await fixture.settle(tester);
  expect(find.text('下载 EPUB 并阅读'), findsOneWidget);
  await tester.binding.handlePopRoute();
  await fixture.settle(tester);
  expect(find.byType(PublicationDetailPage), findsNothing);
}

void _basicNavigationTests() {
  testWidgets('actual router root back confirms instead of exiting Android', (
    tester,
  ) async {
    await fixture.pump(tester);
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    expect(find.text('退出 Zero Player？'), findsOneWidget);
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    expect(find.text('退出 Zero Player？'), findsNothing);
    expect(
      platformCalls
          .where(
            (call) => call.method == 'SystemNavigator.setFrameworkHandlesBack',
          )
          .last
          .arguments,
      isTrue,
    );
    await fixture.finish(tester);
  });

  testWidgets('actual shell scroll hides navigation without an overlay menu', (
    tester,
  ) async {
    await fixture.pump(tester);
    final router = GoRouter.of(tester.element(find.byType(AppShell)));
    router.go('/settings');
    await fixture.settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar).hitTestable(), findsNothing);
    expect(find.byTooltip('展开导航').hitTestable(), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    await fixture.finish(tester);
  });

  testWidgets('phone startup never requests immersive app fullscreen', (
    tester,
  ) async {
    await fixture.pump(tester);
    expect(fixture.fullscreenCalls.where((call) => call.$1), isEmpty);
    expect(find.byType(NavigationBar), findsOneWidget);
    await fixture.finish(tester);
  });
}

void _stackTests() {
  testWidgets('reading keeps its branch state and both return paths', (
    tester,
  ) async {
    await fixture.pump(tester, size: const Size(320, 740));
    final router = GoRouter.of(tester.element(find.byType(AppShell)));
    router.go('/reading');
    await fixture.settle(tester);
    await tester.tap(find.text('书架'));
    await fixture.settle(tester);
    final branch = tester.element(find.byType(BooksPage));
    Navigator.of(branch).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('模块详情')),
          body: const Text('阅读详情'),
        ),
      ),
    );
    await fixture.settle(tester);
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    expect(router.state.uri.path, '/reading');
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .selected,
      {1},
    );
    router.go('/settings');
    await fixture.settle(tester);
    router.go('/reading');
    await fixture.settle(tester);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .selected,
      {1},
    );
    Navigator.of(tester.element(find.byType(BooksPage))).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('模块详情'))),
      ),
    );
    await fixture.settle(tester);
    await tester.tap(find.byType(BackButton));
    await fixture.settle(tester);
    expect(router.state.uri.path, '/reading');
    expect(tester.takeException(), isNull);
    await fixture.finish(tester);
  });

  testWidgets(
    'system back dismisses dialogs, drawer, pushed pages before root exit',
    (tester) async {
      await fixture.pump(tester);
      final context = tester.element(find.byType(AppShell));
      final router = GoRouter.of(context);
      router.push('/calendar');
      await fixture.settle(tester);
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('测试弹窗')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await fixture.settle(tester);
      expect(find.text('测试弹窗'), findsNothing);
      expect(router.state.uri.path, '/calendar');
      await tester.binding.handlePopRoute();
      await fixture.settle(tester);
      expect(router.state.uri.path, '/');
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer).hitTestable(), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer).hitTestable(), findsNothing);
      expect(find.text('退出 Zero Player？'), findsNothing);
      router.go('/settings');
      await fixture.settle(tester);
      await tester.binding.handlePopRoute();
      await fixture.settle(tester);
      expect(router.state.uri.path, '/settings');
      expect(find.text('退出 Zero Player？'), findsOneWidget);
      await tester.tap(find.text('继续使用'));
      await fixture.settle(tester);
      expect(
        platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
        isEmpty,
      );
      await fixture.finish(tester);
    },
  );
}

void _viewportAndExitTests() {
  testWidgets('phone landscape and stored TV mode keep bottom navigation', (
    tester,
  ) async {
    await tester.runAsync(
      () => fixture.services.settings.update({'mode': 'television'}),
    );
    await fixture.pump(tester, size: const Size(844, 390));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(fixture.fullscreenCalls.where((call) => call.$1), isEmpty);
    await fixture.services.platform.fullscreen(true);
    expect(fixture.fullscreenCalls.last, (false, true));
    await fixture.services.platform.fullscreen(false);
    expect(fixture.fullscreenCalls.last, (false, false));
    expect(find.byType(NavigationBar), findsOneWidget);
    await fixture.finish(tester);
  });

  testWidgets('exit is dispatched only after explicit confirmation', (
    tester,
  ) async {
    await fixture.pump(tester);
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    await tester.tap(find.text('继续使用'));
    await tester.pumpAndSettle();
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    await tester.tap(find.text('退出'));
    await fixture.waitFor(
      tester,
      () => platformCalls.any((call) => call.method == 'SystemNavigator.pop'),
    );
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
    await fixture.finish(tester);
  });
}
