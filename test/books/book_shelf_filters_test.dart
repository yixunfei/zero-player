import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  test(
    'shelf update check records additions for books outside follow list',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('book-shelf-filter-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      addTearDown(() async {
        await services.close();
        await root.delete(recursive: true);
      });
      final book = Book(
        'source',
        BookKind.text,
        '书',
        '作者',
        Uri.parse('https://fixture.test/book'),
      );
      final old = BookChapter('第一章', Uri.parse('https://fixture.test/1'));
      final fresh = BookChapter('第二章', Uri.parse('https://fixture.test/2'));
      await services.books.store.saveBook(book, chapters: [old]);
      await services.books.store.updateShelfChapters(book, [old, fresh]);
      final entry = await services.books.store.entry(book);
      expect(entry!.newChapters, 1);
      expect(entry.chapters.map((chapter) => chapter.id), contains(fresh.id));
      await services.books.store.saveText(book, fresh, '离线正文');
      expect(await services.books.store.savedText(book), {fresh.id});
      await services.books.store.clearOffline(book);
      expect(await services.books.store.savedText(book), isEmpty);
      expect((await services.books.store.entry(book))!.newChapters, 1);
    },
  );
}
