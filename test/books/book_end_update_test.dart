import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_reader_page.dart';
import 'package:zero_player/features/books/presentation/reader_pagination.dart';

void main() {
  testWidgets('last chapter asks before checking online updates', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('book-end-update-'),
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
      'test',
      BookKind.text,
      '测试书',
      '作者',
      Uri.parse('https://fixture.test/book'),
    );
    final chapter = BookChapter(
      '第一章',
      Uri.parse('https://fixture.test/chapter'),
    );
    await services.books.store.saveText(book, chapter, '短正文。');
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
    await tester.pumpAndSettle();
    final body = tester.getRect(find.byType(ReaderTapZones));
    await tester.tapAt(Offset(body.right - 10, body.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('已读到当前最后一章'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.text('已读到当前最后一章'), findsNothing);
  });
}
