import 'dart:convert';
import '../../../core/persistence/app_database.dart';
import '../../catalog/domain/catalog_item.dart';
import '../application/content_policy.dart';

Map<String, String> contentRecord(CatalogItem item) => {
  'title': item.title,
  'year': item.year,
  'category': item.category,
  'categoryId': item.categoryId,
  'tags': item.tags,
  'description': item.description,
  'director': item.director,
  'remarks': item.remarks,
};

CatalogItem? recordedItem(Map<String, Object?> row) {
  try {
    final raw = row['content_record'] ?? row['work_json'];
    if (raw is! String) return null;
    final data = jsonDecode(raw) as Map;
    return CatalogItem(
      sourceId: row['source_id'] as String,
      id: row['remote_id'] as String,
      title: data['title'] as String,
      category: data['category'] as String? ?? '',
      categoryId: data['categoryId'] as String? ?? '',
      tags: data['tags'] as String? ?? '',
      description: data['description'] as String? ?? '',
      remarks: data['remarks'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
}

bool recordAllowed(ContentPolicy? policy, Map<String, Object?> row) {
  if (policy == null) return true;
  final item = recordedItem(row);
  if (item == null) return !policy.active && !policy.supervision.corrupted;
  return policy.itemAllowed(item) &&
      policy.textAllowed(
        [
          row['title'],
          row['line_name'],
          row['episode_label'],
        ].whereType<String>().join(' '),
      );
}

Future<void> rememberContent(AppDatabase db, CatalogItem item) =>
    db.atomic(() async {
      await db.customStatement(
        'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        [
          'content_label:${item.sourceId}:${item.id}',
          jsonEncode(contentRecord(item)),
        ],
      );
    }, tables: const {'content_records'});
