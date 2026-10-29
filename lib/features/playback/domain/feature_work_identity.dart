import 'dart:convert';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/domain/work_identity.dart';

/// Cross-channel reuse needs positive work identity, not a fuzzy title alone.
String featureWorkIdentity(CatalogItem item) {
  final title = normalizedTitle(item.title);
  final year = normalizedYear(item.year);
  if (title.isEmpty || (year.isEmpty && item.director.trim().isEmpty)) {
    return jsonEncode(['source', item.sourceId, item.id]);
  }
  return jsonEncode([
    title,
    year.isNotEmpty ? year : item.director.trim(),
    workKind(item.category),
    workVersion(item),
  ]);
}
