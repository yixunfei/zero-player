import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_image_chapter.dart';
import 'package:zero_player/features/books/presentation/book_reader_page.dart';

void main() {
  testWidgets('offline comic opens a decoded image in the reader', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('book-comic-reader-'),
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
      'comic',
      BookKind.comic,
      '测试漫画',
      '作者',
      Uri.parse('https://fixture.test/book'),
    );
    final chapter = BookChapter('第一话', Uri.parse('https://fixture.test/1'));
    final image = Uri.parse('https://fixture.test/1.png');
    await services.books.store.saveOfflineImages(book, chapter, {
      image: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      ),
    }, () async {});
    await tester.pumpWidget(
      MaterialApp(
        home: BookReaderPage(
          repository: services.books,
          book: book,
          chapters: [chapter],
          initial: chapter,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BookImageChapter), findsOneWidget);
    final imageView = find.byType(RawImage, skipOffstage: false).first;
    expect(tester.renderObject<RenderImage>(imageView).image, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 250));
    final scrollable = find.descendant(
      of: find.byType(BookImageChapter),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });
}
