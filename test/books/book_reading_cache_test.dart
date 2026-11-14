import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/book_store.dart';
import 'package:zero_player/features/books/data/book_mixed_content.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  test('reading cache clears without removing offline chapters', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = BookStore(db);
    final book = Book(
      'test',
      BookKind.text,
      '测试',
      '',
      Uri.parse('https://fixture.test/book'),
    );
    final chapter = BookChapter('第一章', Uri.parse('https://fixture.test/1'));
    await store.cacheReading(book, chapter, '自动缓存');
    final image = Uri.parse('https://fixture.test/pages/1.png');
    await store.cacheReadingImage(book, image, [137, 80, 78, 71]);
    await store.cacheMixedReading(book, chapter, [
      const BookTextSegment('图前文字'),
      BookImageSegment(image),
    ]);
    await store.saveText(book, chapter, '离线下载');
    expect(await store.readingCache(book, chapter), '自动缓存');
    expect(await store.readingImage(book, image), [137, 80, 78, 71]);
    expect(await store.mixedReading(book, chapter), hasLength(2));
    await store.clearReadingCache(book);
    expect(await store.readingCache(book, chapter), isNull);
    expect(await store.readingImage(book, image), isNull);
    expect(await store.mixedReading(book, chapter), isEmpty);
    expect(await store.text(book, chapter), '离线下载');
  });

  test('offline comic images survive reading cache cleanup', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = BookStore(db);
    final book = Book(
      'comic',
      BookKind.comic,
      '漫画',
      '',
      Uri.parse('https://fixture.test/comic'),
    );
    final chapter = BookChapter('第一话', Uri.parse('https://fixture.test/1'));
    final address = Uri.parse('https://fixture.test/1.png');
    await store.saveOfflineImages(book, chapter, {
      address: [1, 2, 3],
    }, () async {});
    await store.cacheReadingImage(book, address, [4, 5, 6]);
    expect(await store.savedImages(book), contains(chapter.id));
    await store.clearReadingCache(book);
    expect(await store.readingImage(book, address), isNull);
    expect(await store.offlineImages(book, chapter), {
      address: [1, 2, 3],
    });
    await store.deleteImages(book, chapter);
    expect(await store.savedImages(book), isEmpty);
  });
}
