import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_search_page.dart';

void main() {
  Book edition(String latest, String updated) => Book(
    'source',
    BookKind.text,
    '同一本书',
    '作者',
    Uri.parse('https://fixture.test/book'),
    latestChapter: latest,
    updatedLabel: updated,
  );

  test('same-day catalog time and chapter progress determine freshness', () {
    final morning = edition('第 100 章', '2026-11-14 08:30');
    final evening = edition('第 99 章', '2026年11月14日 21:15');
    expect(compareBookChapterFreshness(evening, morning), lessThan(0));
    final newest = edition('第 102 回', '2026-11-14 21:15');
    expect(compareBookChapterFreshness(newest, evening), lessThan(0));
    final manga = edition('第 103 话', '2026-11-14 21:15');
    expect(compareBookChapterFreshness(manga, newest), lessThan(0));
  });
}
