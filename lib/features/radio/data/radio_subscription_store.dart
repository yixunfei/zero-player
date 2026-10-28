import 'dart:convert';
import '../../../core/persistence/app_database.dart';
import '../domain/radio_subscription.dart';

final class RadioSubscriptionStore {
  const RadioSubscriptionStore(this.db, this.source);
  final AppDatabase db;
  final Uri source;

  Future<List<RadioSubscription>> read() async {
    final rows = await db.rows(
      "SELECT value FROM app_meta WHERE key='radio_subscriptions'",
    );
    if (rows.isEmpty) return [RadioSubscription(name: '内置广播', url: source)];
    final data = jsonDecode(rows.single['value'] as String);
    if (data is! List || data.length > 50) {
      throw const FormatException('广播订阅配置无效');
    }
    return data.map((row) {
      if (row is! Map) throw const FormatException('广播订阅配置无效');
      return RadioSubscription.fromJson(row);
    }).toList();
  }

  Future<void> update(
    List<RadioSubscription> Function(List<RadioSubscription>) change,
  ) => db.atomic(() async {
    final next = change(await read());
    if (next.length > 50) throw const FormatException('广播订阅最多 50 个');
    final unique = {for (final item in next) item.id: item};
    await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      'radio_subscriptions',
      jsonEncode(unique.values.map((s) => s.toJson()).toList()),
    ]);
  }, tables: const {'app_meta'});
}
