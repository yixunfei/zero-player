import '../../catalog/domain/catalog_item.dart';

enum SearchMatch { broad, contains, exact }

enum SearchSort { source, relevance, newest }

/// Local filters apply only to metadata actually returned by the provider.
final class SearchOptions {
  const SearchOptions({
    this.match = SearchMatch.broad,
    this.sort = SearchSort.source,
    this.year = '',
    this.area = '',
    this.category = '',
    this.excludeWords = '',
    this.maxPages = 5,
  });
  final SearchMatch match;
  final SearchSort sort;
  final String year, area, category, excludeWords;
  final int maxPages;
  static String normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  bool accepts(CatalogItem item, String query) {
    final title = normalize(item.title);
    final term = normalize(query);
    if (match == SearchMatch.exact && title != term) return false;
    if (match == SearchMatch.contains && !title.contains(term)) return false;
    if (year.trim().isNotEmpty && item.year.trim() != year.trim()) return false;
    if (area.trim().isNotEmpty &&
        !normalize(item.area).contains(normalize(area))) {
      return false;
    }
    if (category.trim().isNotEmpty &&
        !normalize(item.category).contains(normalize(category))) {
      return false;
    }
    final metadata = normalize(
      '${item.title} ${item.category} ${item.remarks}',
    );
    return !excludeWords
        .split(RegExp(r'[,，\s]+'))
        .where((s) => s.isNotEmpty)
        .any((word) => metadata.contains(normalize(word)));
  }
}
