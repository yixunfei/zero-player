import '../../domain/book.dart';
import '../../domain/legado_source.dart';
import 'legado_request.dart';
import 'legado_rule_tokens.dart';

List<LegadoCategory> legadoCategories(Object? raw) => _categories(
  raw,
  0,
).where((item) => item.address.isNotEmpty).take(512).toList();

Iterable<LegadoCategory> _categories(Object? raw, int depth) sync* {
  if (depth > 4) return;
  if (raw is List) {
    for (final item in raw) {
      yield* _categories(item, depth + 1);
    }
    return;
  }
  if (raw is Map) {
    final url = raw['url'];
    if (url is String) {
      yield LegadoCategory(bookLabel(raw['title'] ?? raw['name']), url.trim());
    }
    return;
  }
  if (raw is! String || raw.trim().isEmpty) return;
  final text = raw.trim();
  if (text.startsWith('[')) {
    Object? decoded;
    try {
      decoded = decodeLegadoJson(text);
    } on FormatException {
      return;
    }
    yield* _categories(decoded, depth + 1);
    return;
  }
  if (legadoScriptMarker.matchAsPrefix(text) != null) {
    yield LegadoCategory('', text);
    return;
  }
  for (final line in splitLegadoRule(text, '\n')) {
    for (final part in splitLegadoRule(line, '&&')) {
      final pair = splitLegadoRule(part, '::');
      yield pair.length == 1
          ? LegadoCategory('', part)
          : LegadoCategory(bookLabel(pair.first), pair.skip(1).join('::'));
    }
  }
}
