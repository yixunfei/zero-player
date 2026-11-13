import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/books/data/rich_book.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/rich_reader_page.dart';
import 'package:zero_player/features/books/presentation/books_page.dart';
import 'package:zero_player/features/books/presentation/book_detail_page.dart';
import 'package:zero_player/features/books/presentation/publication_detail_page.dart';
import 'package:zero_player/features/books/presentation/technical_book_page.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import '../test_support/public_book_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _onlineSample();
  _technicalSample();
  testWidgets(
    'PDF native render, outline, text search, zoom and page navigation',
    (tester) async {
      await _withServices((services) async {
        final file = await File(
          '${services.root.path}/sample.pdf',
        ).writeAsBytes(samplePdf());
        final book = await services.books.importLocal(file);
        final doc = await PdfDocument.openFile(file.path);
        expect(doc.pages, hasLength(2));
        expect((await doc.loadOutline()).single.title, 'Second chapter');
        expect(
          (await doc.pages.first.loadText())?.fullText,
          contains('Hello Technical Book'),
        );
        final image = await doc.pages.first.render(width: 300, height: 400);
        expect(image, isNotNull);
        expect(image!.pixels.length, greaterThan(1000));
        image.dispose();
        await doc.dispose();
        await tester.pumpWidget(
          MaterialApp(
            home: RichReaderPage(
              repository: services.books,
              book: book,
              file: services.books.documentFile(book, 'pdf'),
            ),
          ),
        );
        await _wait(tester, () => find.byTooltip('阅读菜单').evaluate().isNotEmpty);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(PdfViewer)),
          MediaQuery.sizeOf(tester.element(find.byType(RichReaderPage))),
        );
        await tester.tap(find.byTooltip('阅读菜单'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Technical');
        await _wait(tester, () => find.text('2 项').evaluate().isNotEmpty);
        await tester.tap(find.byTooltip('放大'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('下一页'));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        await _wait(tester, () => find.byTooltip('阅读菜单').evaluate().isNotEmpty);
        final saved = await services.books.store.entry(book);
        expect(saved!.last, saved.chapters[1].id);
        await tester.tap(find.byTooltip('阅读菜单'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Technical');
        await _wait(tester, () => find.text('1 / 2').evaluate().isNotEmpty);
        expect(find.byType(TextField), findsOneWidget);
        await _wait(tester, () => find.text('2 项').evaluate().isNotEmpty);
        await tester.tap(find.byTooltip('下个结果'));
        await _wait(tester, () => find.text('2 / 2').evaluate().isNotEmpty);
        expect(find.byType(TextField), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    },
  );
  _epubSample();
  _epubSearchAndContents();
}

void _epubSearchAndContents() {
  testWidgets('EPUB search dismissal restores the chapter and its position', (
    tester,
  ) async {
    await _withServices((services) async {
      final archive = ZipDecoder().decodeBytes(sampleEpub(paragraphs: 100));
      final manifest = utf8.decode(archive.findFile('OEBPS/book.opf')!.content);
      archive.addFile(
        ArchiveFile.string(
          'OEBPS/book.opf',
          manifest
              .replaceFirst(
                '</manifest>',
                '<item id="b" href="second.xhtml" media-type="application/xhtml+xml"/></manifest>',
              )
              .replaceFirst('</spine>', '<itemref idref="b"/></spine>'),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          'OEBPS/second.xhtml',
          '<h1>第二章</h1>${'<p>独有正文。</p>' * 120}',
        ),
      );
      final file = await File(
        '${services.root.path}/search.epub',
      ).writeAsBytes(ZipEncoder().encode(archive));
      final book = await services.books.importLocal(file);
      final store = services.books.store;
      final entry = (await store.entry(book))!;
      final key = 'rich_position_${book.id}';
      final screen = MaterialApp(
        home: RichReaderPage(
          repository: services.books,
          book: book,
          file: services.books.documentFile(book, 'epub'),
        ),
      );
      await tester.pumpWidget(screen);
      await _wait(tester, () => find.byType(HtmlWidget).evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      final offset = _epubScroll(tester).offset;
      expect(offset, greaterThan(0));
      await _epubSearch(tester, '找不到的关键词');
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      expect(_epubScroll(tester).offset, closeTo(offset, 1));
      await _epubSearch(tester, '找不到的关键词');
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(_epubScroll(tester).offset, closeTo(offset, 1));
      await _epubSearch(tester, '独有正文');
      await tester.tap(find.widgetWithText(ListTile, '第二章'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(_epubScroll(tester).offset, 0);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '第一章'));
      await tester.pumpAndSettle();
      expect(_epubScroll(tester).offset, 0);
      expect((await store.read(key) as Map)['offset'], 0);
      expect((await store.entry(book))!.last, entry.chapters.first.id);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _epubSearch(WidgetTester tester, String query) async {
  await tester.tap(find.byTooltip('阅读菜单'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
  expect(find.byType(HtmlWidget), findsNothing);
}

ScrollController _epubScroll(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(
      find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.controller != null,
      ),
    )
    .controller!;

void _epubSample() {
  testWidgets(
    'EPUB image and code, vertical text, file above old 12 MiB limit',
    (tester) async {
      await _withServices((services) async {
        final archive = ZipDecoder().decodeBytes(
          sampleEpub(vertical: true, paragraphs: 30),
        );
        final padding = Uint8List(13 * 1024 * 1024);
        for (var i = 0; i < padding.length; i++) {
          padding[i] = i % 251;
        }
        archive.addFile(
          ArchiveFile('padding.dat', padding.length, padding)
            ..compression = CompressionType.none,
        );
        final bytes = ZipEncoder().encode(archive);
        expect(bytes.length, greaterThan(12 * 1024 * 1024));
        final file = await File(
          '${services.root.path}/vertical.epub',
        ).writeAsBytes(bytes);
        final book = await services.books.importLocal(file);
        expect(readRichEpub(bytes).single.vertical, isTrue);
        final captureKey = GlobalKey();
        final screen = RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            home: RichReaderPage(
              repository: services.books,
              book: book,
              file: services.books.documentFile(book, 'epub'),
            ),
          ),
        );
        await tester.pumpWidget(screen);
        await _wait(tester, () => find.text('漢').evaluate().isNotEmpty);
        expect(find.text('h\nà\nn'), findsOneWidget);
        await _captureEpub(captureKey, 'vertical');
        await tester.tap(find.byTooltip('下一页'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<HtmlWidget>(find.byType(HtmlWidget).first).html,
          contains('data:image/svg+xml;base64,'),
        );
        await tester.tap(find.byTooltip('下一页'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('docker run', findRichText: true),
          findsWidgets,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(screen);
        await _wait(
          tester,
          () => find
              .textContaining('docker run', findRichText: true)
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byTooltip('阅读菜单'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('切换横排／竖排'));
        await tester.pumpAndSettle();
        await _checkEpubPaging(tester);
        await _captureEpub(captureKey, 'horizontal');
        await tester.tap(find.byTooltip('下一页'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(screen);
        await _wait(
          tester,
          () => find.byType(HtmlWidget).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SingleChildScrollView>(
                find.byWidgetPredicate(
                  (w) => w is SingleChildScrollView && w.controller != null,
                ),
              )
              .controller!
              .offset,
          greaterThan(0),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    },
  );
}

Future<void> _checkEpubPaging(WidgetTester tester) async {
  final scroll = _epubScroll(tester);
  await tester.tap(find.byTooltip('下一页'));
  await tester.pumpAndSettle();
  expect(scroll.offset, greaterThan(0));
  expect(find.byTooltip('目录'), findsNothing);
  await tester.tap(find.byTooltip('上一页'));
  await tester.pumpAndSettle();
  expect(scroll.offset, 0);
}

void _onlineSample() {
  testWidgets(
    'Gutenberg Virgil 228 downloads and imports real EPUB',
    (tester) async {
      await _withServices((services) async {
        final uri = Uri.parse(
          'https://www.gutenberg.org/cache/epub/228/pg228-images-3.epub',
        );
        final result = await services.books.client.network.get(
          uri,
          cancellation: CancellationToken(),
          validateTarget: (u) {
            if (u.host != uri.host) {
              throw const FormatException('unexpected host');
            }
          },
        );
        final book = await _downloadPublicationThroughLibrary(tester, services);
        expect(book.title, contains('Aeneid'));
        expect(book.author, contains('Virgil'));
        final rich = await readRichEpubOffThread(result.bytes);
        final entry = await services.books.store.entry(book);
        expect(entry!.chapters.length, rich.length);
        expect(rich.length, greaterThan(10));
        expect(rich.any((s) => s.text.contains('Dryden')), isTrue);
      });
    },
    skip: !const bool.fromEnvironment('RUN_PUBLIC_CATALOG_ONLINE'),
  );
}

Future<Book> _downloadPublicationThroughLibrary(
  WidgetTester tester,
  AppServices services,
) async {
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BooksPage(services: services, kind: BookKind.text),
        ),
      ),
    );
    await tester.tap(find.text('出版书目'));
    await _wait(tester, () => find.byType(TextField).evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextField), 'The Aeneid');
    final result = find.widgetWithText(ListTile, 'The Aeneid');
    await _wait(tester, () => result.evaluate().isNotEmpty);
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(find.byType(PublicationDetailPage), findsOneWidget);
    await tester.tap(find.text('下载 EPUB 并阅读'));
    await _wait(
      tester,
      () => find.text('开始阅读').evaluate().isNotEmpty,
      attempts: 450,
    );
    final book = tester
        .widget<BookDetailPage>(find.byType(BookDetailPage))
        .initial;
    await tester.ensureVisible(find.text('开始阅读'));
    await tester.tap(find.text('开始阅读'));
    final reader = find.byType(RichReaderPage);
    final content = find.descendant(
      of: reader,
      matching: find.byType(HtmlWidget),
    );
    await _wait(tester, () => content.evaluate().isNotEmpty);
    expect(tester.widget<HtmlWidget>(content.first).html, isNotEmpty);
    return book;
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
}

void _technicalSample() {
  testWidgets(
    'Bookstack real directory and technical HTML with code',
    (tester) async {
      await _withServices((services) async {
        await _openTechnicalFromLibrary(tester, services);
        await _wait(
          tester,
          () => find.textContaining('安全容器运行时').evaluate().isNotEmpty,
        );
        await tester.tap(find.textContaining('安全容器运行时').first);
        await _wait(
          tester,
          () => find.byType(HtmlWidget).evaluate().isNotEmpty,
        );
        final body = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
        expect(body.html, contains('Kata Containers'));
        expect(body.html, contains('<code>'));
        expect(body.html, isNot(contains('<script')));
        await tester.tap(find.byTooltip('章节目录'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('3.7 macOS'),
          300,
          scrollable: find.byType(Scrollable),
        );
        await tester.tap(find.text('3.7 macOS'));
        await _wait(
          tester,
          () => find
              .byWidgetPredicate(
                (widget) =>
                    widget is HtmlWidget &&
                    widget.html.contains('Docker Desktop'),
              )
              .evaluate()
              .isNotEmpty,
        );
        await _wait(
          tester,
          () => find
              .byWidgetPredicate(
                (widget) =>
                    widget is HtmlWidget &&
                    widget.html.contains('data:image/jpeg;base64,'),
              )
              .evaluate()
              .isNotEmpty,
          attempts: 400,
        );
        final illustrated = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
        expect(illustrated.html, contains('data:image/jpeg;base64,'));
        expect(illustrated.html, isNot(contains('loading.gif')));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    },
    skip: !const bool.fromEnvironment('RUN_PUBLIC_CATALOG_ONLINE'),
  );
}

Future<void> _openTechnicalFromLibrary(
  WidgetTester tester,
  AppServices services,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BooksPage(services: services, kind: BookKind.text),
      ),
    ),
  );
  await tester.tap(find.text('出版书目'));
  await _wait(
    tester,
    () => find.widgetWithText(ChoiceChip, '技术图书').evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ChoiceChip, '技术图书'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Docker 从入门到实践'));
  await tester.pumpAndSettle();
  expect(find.byType(PublicationDetailPage), findsOneWidget);
  await tester.tap(find.text('应用内阅读'));
  await _wait(
    tester,
    () => find.byType(TechnicalBookPage).evaluate().isNotEmpty,
  );
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready, {
  int attempts = 120,
}) async {
  for (var i = 0; i < attempts && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(
    ready(),
    isTrue,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .take(12)
        .join('\n'),
  );
}

Future<void> _withServices(Future<void> Function(AppServices) run) async {
  final root = await Directory.systemTemp.createTemp('public-reading-');
  final services = AppServices.scoped(root, AppDatabase.memory());
  try {
    await services.settings.load();
    await services.supervision.load();
    await run(services);
  } finally {
    await services.close();
    await root.delete(recursive: true);
  }
}

Future<void> _captureEpub(GlobalKey key, String name) async {
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
    await File(
      '$root/build/epub-$name.png',
    ).writeAsBytes(png.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
