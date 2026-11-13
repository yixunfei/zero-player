import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/data/book_store.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/books_repository.dart';
import 'package:zero_player/features/books/data/legado/legado_worker.dart';
import 'package:zero_player/features/books/presentation/book_reader_page.dart';
import 'package:zero_player/features/books/presentation/reader_pagination.dart';
import 'package:zero_player/features/books/presentation/reader_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pagination preserves Chinese, newlines and emoji at multiple sizes',
    () {
      final text = List.filled(60, '章节正文，分页不能遗漏文字。你好🌍！\n另一段文字。\n').join();
      for (final size in [const Size(280, 360), const Size(700, 600)]) {
        for (final scale in [1.0, 1.5]) {
          final pages = paginateReadingText(
            text,
            const TextStyle(fontSize: 21, height: 1.8),
            size,
            TextScaler.linear(scale),
            TextDirection.ltr,
          );
          expect(pages.length, greaterThan(1));
          expect(pages.join(), text);
          expect(pages.every((page) => page.isNotEmpty), isTrue);
          for (final page in pages) {
            final painter = TextPainter(
              text: TextSpan(
                text: page.trimRight(),
                style: const TextStyle(fontSize: 21, height: 1.8),
              ),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout(maxWidth: size.width);
            expect(painter.height, lessThanOrEqualTo(size.height + 1));
            painter.dispose();
          }
        }
      }
    },
  );
  test(
    'annotations persist independently and removal cleans local notes',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final store = BookStore(db);
      final book = Book(
        'local',
        BookKind.text,
        '测试',
        '',
        Uri.parse('book:test'),
      );
      await Future.wait([
        for (var i = 0; i < 3; i++)
          store.addAnnotation(book, {'id': '$i', 'note': '笔记$i'}),
      ]);
      expect(await store.annotations(book), hasLength(3));
      await store.deleteAnnotation(book, '1');
      expect(
        (await store.annotations(book)).map((e) => e['id']),
        isNot(contains('1')),
      );
      await store.removeLocal(book);
      expect(await store.annotations(book), isEmpty);
    },
  );
  test('Legado cover and genre survive parsing and serialization', () async {
    final parsed = parseBookSources(
      '''{"bookSourceName":"测试","bookSourceUrl":"https://books.test","searchUrl":"/search?q={{key}}","ruleSearch":{"bookList":".book","name":"a@text","bookUrl":"a@href","coverUrl":"img@src","kind":"span@text"},"ruleContent":{"content":"#body@text"}}''',
    );
    final source = parsed.sources.single;
    final result = await runLegadoJob(
      LegadoJob(
        source,
        source.endpoint,
        LegadoOperation.books,
        input:
            '<div class="book"><a href="/one">测试书</a><img src="/cover.jpg"><span>历史</span></div>',
      ),
      CancellationToken(),
    );
    final restored = Book.fromJson(result.books.single.toJson());
    expect(restored.cover, 'https://books.test/cover.jpg');
    expect(restored.category, '历史');
  });
  _readerWidgetTest(const Size(320, 640));
  _readerWidgetTest(const Size(390, 844));
  _readerWidgetTest(const Size(1280, 720));
  for (final mode in ReaderTurnMode.values) {
    _readerGestureTest(mode);
  }
  _fallbackTest();
}

Future<void> _saveTestNote(
  WidgetTester tester,
  AppServices services,
  Book book,
) async {
  await tester.tap(find.byTooltip('添加书签或笔记'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '测试笔记');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
  expect((await services.books.store.annotations(book)).single['note'], '测试笔记');
}

void _readerWidgetTest(Size size) {
  testWidgets('reader pages, chapters, notes and style work at $size', (
    tester,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('reader-ui-'),
    ))!;
    final services = AppServices.scoped(root, AppDatabase.memory());
    addTearDown(() async {
      await tester.runAsync(() async {
        await services.close();
        await root.delete(recursive: true);
      });
    });
    await services.settings.load();
    await services.supervision.load();
    final book = Book(
      'local',
      BookKind.text,
      '测试书',
      '作者',
      Uri.parse('book:test'),
    );
    final chapters = [
      BookChapter('第一章', Uri.parse('book:test#1')),
      BookChapter('第二章', Uri.parse('book:test#2')),
    ];
    await services.books.store.saveTexts(book, {
      for (final chapter in chapters)
        chapter: List.filled(20, '这是一段用于验证分页与阅读进度的正文。').join('\n'),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BookReaderPage(
          repository: services.books,
          book: book,
          chapters: chapters,
          initial: chapters.first,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1 /'), findsOneWidget);
    final body = tester.getRect(find.byType(ReaderTapZones));
    await tester.tapAt(Offset(body.right - 10, body.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 /'), findsOneWidget);
    final viewport = tester.getRect(find.byType(ReaderViewport));
    await tester.dragFrom(
      Offset(viewport.left + viewport.width * .18, viewport.center.dy),
      Offset(viewport.width * .69, 0),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1 /'), findsOneWidget);
    await tester.tapAt(Offset(body.right - 10, body.center.dy));
    await tester.pumpAndSettle();
    await tester.tapAt(body.center);
    await tester.pumpAndSettle();
    await _saveTestNote(tester, services, book);
    await tester.tap(find.byTooltip('章节目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一章'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('阅读菜单'));
    await tester.pumpAndSettle();
    expect(find.text('第二章'), findsOneWidget);
    await tester.tap(find.byTooltip('书签与笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一章'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 /'), findsOneWidget);
    if (find.byTooltip('阅读样式').evaluate().isEmpty) {
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('阅读样式'));
    await tester.pumpAndSettle();
    final paperChip = find.widgetWithText(ChoiceChip, '护眼');
    expect(paperChip, findsOneWidget);
    await tester.ensureVisible(paperChip);
    await tester.tap(paperChip);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(paperChip).selected, isTrue);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(
      (await services.books.store.read('books_reader_preferences')
          as Map)['paper'],
      'green',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

void _readerGestureTest(ReaderTurnMode mode) {
  testWidgets('reader crosses chapters with ${mode.name} gestures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('reader-gestures-'),
    ))!;
    final services = AppServices.scoped(root, AppDatabase.memory());
    addTearDown(
      () => tester.runAsync(() async {
        await services.close();
        await root.delete(recursive: true);
      }),
    );
    await services.settings.load();
    await services.supervision.load();
    final book = Book(
      'local',
      BookKind.text,
      '测试书',
      '',
      Uri.parse('book:gestures'),
    );
    final chapters = [
      BookChapter('第一章', Uri.parse('book:gestures#1')),
      BookChapter('第二章', Uri.parse('book:gestures#2')),
    ];
    await services.books.store.write(
      'books_reader_preferences',
      ReaderPreferences(mode: mode).toJson(),
    );
    await services.books.store.saveTexts(book, {
      for (final chapter in chapters) chapter: '同一段足以显示在一页的文本。',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BookReaderPage(
          repository: services.books,
          book: book,
          chapters: chapters,
          initial: chapters.first,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final body = find.byType(ReaderViewport);
    final swipe = mode.horizontal
        ? const Offset(-220, 0)
        : const Offset(0, -240);
    await tester.drag(body, swipe);
    await tester.pumpAndSettle();
    expect((await services.books.store.entry(book))?.last, chapters.last.id);
    await tester.drag(body, -swipe);
    await tester.pumpAndSettle();
    expect((await services.books.store.entry(book))?.last, chapters.first.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

void _fallbackTest() {
  test(
    'online reader safely falls back and honors cancellation and opt-out',
    () async {
      final root = await Directory.systemTemp.createTemp('reader-fallback-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      await services.settings.load();
      await services.supervision.load();
      final repository = services.books;
      for (final source in await repository.sources(BookKind.text)) {
        await repository.store.saveSource(source.source, {'enabled': false});
      }
      final source = BookSource.fromJson({
        'name': '备用',
        'kind': 'text',
        'format': 'featured',
        'url': 'https://backup.test',
        'featured': [
          {'title': '同一本书', 'author': '作者', 'url': '/book'},
        ],
        'rules': {
          'chapters': 'a',
          'chapterTitle': '@text',
          'chapterUrl': '@href',
          'content': 'p@text',
        },
      });
      await repository.importSources([source]);
      await repository.saveSource(source, {'enabled': true});
      final original = Book(
        'missing',
        BookKind.text,
        '同一本书',
        '作者',
        Uri.parse('https://original.test/book'),
      );
      final chapter = BookChapter(
        '第一章 开篇',
        Uri.parse('https://original.test/1'),
      );
      final alternate = source.featured.single;
      final matching = BookChapter(
        '第一章：开篇',
        Uri.parse('https://backup.test/1'),
      );
      await repository.store.saveBook(alternate, chapters: [matching]);
      await repository.store.saveText(alternate, matching, '备用章节正文');
      final result = await repository.readWithFallback(
        original,
        chapter,
        CancellationToken(),
      );
      expect(result.text, '备用章节正文');
      expect(result.sourceBook.id, alternate.id);
      await _checkFallbackContent(repository, original, chapter);
      await expectLater(
        repository.readWithFallback(
          original,
          chapter,
          CancellationToken(),
          automatic: false,
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.readWithFallback(
          original,
          chapter,
          CancellationToken()..cancel(),
        ),
        throwsA(isA<Exception>()),
      );
      await repository.store.saveBook(
        alternate,
        chapters: [
          matching,
          BookChapter('第一章 开篇', Uri.parse('https://backup.test/duplicate')),
        ],
      );
      await expectLater(
        repository.readWithFallback(original, chapter, CancellationToken()),
        throwsFormatException,
      );
      expect(await repository.store.text(original, chapter), isNull);
    },
  );
}

Future<void> _checkFallbackContent(
  BooksRepository repository,
  Book original,
  BookChapter chapter,
) async {
  await repository.store.saveText(original, chapter, ' \n ');
  expect(
    (await repository.readWithFallback(
      original,
      chapter,
      CancellationToken(),
    )).text,
    '备用章节正文',
  );
  await repository.store.saveText(original, chapter, '色情');
  await expectLater(
    repository.readWithFallback(original, chapter, CancellationToken()),
    throwsFormatException,
  );
  await repository.store.deleteText(original, chapter);
}
