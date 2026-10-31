import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/search/application/search_options.dart';

void main() {
  const movie = CatalogItem(
    sourceId: 'a',
    id: '1',
    title: ' Movie Name ',
    year: '2026',
    area: '中国大陆',
    category: '剧情',
    remarks: '预告片',
  );
  test(
    'exact matching normalizes case and spaces without conflating sequels',
    () {
      const options = SearchOptions(match: SearchMatch.exact);
      expect(options.accepts(movie, 'movie name'), isTrue);
      expect(options.accepts(movie, 'movie'), isFalse);
      expect(
        const SearchOptions(
          match: SearchMatch.contains,
        ).accepts(movie, 'movie'),
        isTrue,
      );
    },
  );
  test('filters combine and missing metadata does not satisfy a filter', () {
    expect(
      const SearchOptions(
        year: '2026',
        area: '大陆',
        category: '剧情',
      ).accepts(movie, ''),
      isTrue,
    );
    expect(const SearchOptions(year: '2025').accepts(movie, ''), isFalse);
    expect(
      const SearchOptions(excludeWords: '花絮，预告').accepts(movie, ''),
      isFalse,
    );
    expect(
      const SearchOptions(
        area: '大陆',
      ).accepts(const CatalogItem(sourceId: 'a', id: '2', title: 'Movie'), ''),
      isFalse,
    );
  });
}
