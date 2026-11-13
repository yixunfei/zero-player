import 'book.dart';

enum BookSearchField { all, title, author }

/// Some site search endpoints return recommendations for unknown terms.
final class BookSearchQuery {
  BookSearchQuery(String input, this.field)
    : _key = _searchKey(input),
      _words = input
          .trim()
          .split(RegExp(r'\s+'))
          .map(_searchKey)
          .where((word) => word.isNotEmpty)
          .toList();

  final BookSearchField field;
  final String _key;
  final List<String> _words;

  int? rank(Book book) {
    if (_key.isEmpty) return null;
    final title = field == BookSearchField.author
        ? null
        : _rankField(book.title);
    final author = field == BookSearchField.title
        ? null
        : _rankField(bookAuthorName(book.author));
    if (author == null) return title == null ? null : title * 2;
    if (title == null || author < title) return author * 2 + 1;
    return title * 2;
  }

  int? _rankField(String value) {
    final key = _searchKey(value);
    if (key == _key) return 0;
    if (key.startsWith(_key)) return 1;
    if (key.contains(_key)) return 2;
    if (_words.length > 1 && _words.every(key.contains)) return 3;
    return null;
  }
}

final _authorPrefix = RegExp(
  r'^(?:作\s*者|著\s*者|by)\s*[:：]\s*',
  caseSensitive: false,
);
final _authorQualifier = RegExp(r'^[\[【〔（(][^\]】〕）)]{1,6}[\]】〕）)]\s*(?=\S)');
final _searchSeparators = RegExp(r'[^\p{L}\p{M}\p{N}+#]', unicode: true);

String bookAuthorName(String value) => value
    .trim()
    .replaceFirst(_authorPrefix, '')
    .replaceFirst(_authorQualifier, '');

String _searchKey(String input) => String.fromCharCodes(
  input.runes.map(
    (code) => code >= 0xff01 && code <= 0xff5e ? code - 0xfee0 : code,
  ),
).toLowerCase().replaceAll(_searchSeparators, '');
