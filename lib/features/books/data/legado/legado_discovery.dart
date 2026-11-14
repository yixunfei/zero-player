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
    var group = '';
    for (final item in raw) {
      for (final category in _categories(item, depth + 1)) {
        if (category.address.isEmpty) {
          group = category.title;
        } else {
          yield LegadoCategory(
            category.title,
            category.address,
            group: category.group.isEmpty ? group : category.group,
          );
        }
      }
    }
    return;
  }
  if (raw is Map) {
    final url = raw['url'];
    if (url is String) {
      yield LegadoCategory(
        bookLabel(raw['title'] ?? raw['name']),
        url.trim(),
        group: bookLabel(raw['group']),
      );
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
  var group = '';
  for (final line in splitLegadoRule(text, '\n')) {
    for (final part in splitLegadoRule(line, '&&')) {
      final pair = splitLegadoRule(part, '::');
      if (pair.length == 1) {
        if (part.isNotEmpty) yield LegadoCategory('', part, group: group);
        continue;
      }
      final title = bookLabel(pair.first);
      final address = pair.skip(1).join('::');
      if (address.isEmpty) {
        group = title;
      } else {
        yield LegadoCategory(title, address, group: group);
      }
    }
  }
}
