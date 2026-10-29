import 'dart:convert';
import '../../../core/persistence/app_database.dart';
import 'feature_rule.dart';

final class FeatureRepository {
  FeatureRepository(this.db, {this.authorize});
  final void Function()? authorize;
  final AppDatabase db;
  static const prefix = 'filter_feature:';

  Future<List<FeatureRule>> list({String? sourceId}) async {
    final rows = await db.rows(
      "SELECT value FROM app_meta WHERE key GLOB 'filter_feature:*' ORDER BY key",
    );
    if (rows.length > 500) throw const FormatException('特征规则超过 500 条上限');
    return rows
        .map((r) => FeatureRule.fromJson(jsonDecode(r['value'] as String)))
        .where((r) => sourceId == null || r.sourceId == sourceId)
        .toList();
  }

  Future<void> save(FeatureRule rule) async {
    final text = jsonEncode(rule.toJson());
    if (text.length > 100000) throw const FormatException('特征数据过大');
    FeatureRule.fromJson(jsonDecode(text));
    await db.atomic(() async {
      final existing = await list();
      if (existing.any((r) => r.id == rule.id)) authorize?.call();
      final remaining = existing.where((r) => r.id != rule.id).toList();
      if (remaining.length >= 500 ||
          remaining.where((r) => r.sourceId == rule.sourceId).length >= 100) {
        throw const FormatException('最多保存 500 条特征，每个渠道最多 100 条');
      }
      await db.customStatement(
        'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
        ['$prefix${rule.id}', text],
      );
    }, tables: {'app_meta'});
  }

  Future<List<FeatureRule>> applicable({
    required String sourceId,
    required String seriesKey,
    bool enabledOnly = false,
  }) async => (await list())
      .where(
        (rule) =>
            rule.appliesTo(source: sourceId, series: seriesKey) &&
            (!enabledOnly || rule.enabled),
      )
      .toList();

  Future<void> setEnabled(FeatureRule rule, bool enabled) =>
      save(rule.copyWith(enabled: enabled));
  Future<void> remove(String id) async {
    authorize?.call();
    await db.write('DELETE FROM app_meta WHERE key=?', ['$prefix$id']);
  }
}
