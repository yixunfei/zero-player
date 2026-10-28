import 'dart:convert';
import '../domain/radio_subscription.dart';
import 'radio_snapshot.dart';

bool validateRadioMetadata(String key, String value) {
  if (key == 'radio_subscriptions') {
    final rows = jsonDecode(value);
    if (rows is! List || rows.length > 50) {
      throw const FormatException('广播订阅数量无效');
    }
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map || !seen.add(RadioSubscription.fromJson(row).id)) {
        throw const FormatException('广播订阅无效或重复');
      }
    }
    return true;
  }
  if (key.startsWith('radio_favorite:')) {
    if (!RegExp(r'^radio_favorite:[a-f0-9]{64}$').hasMatch(key) ||
        !{'true', 'false'}.contains(value)) {
      throw const FormatException('广播收藏无效');
    }
    return true;
  }
  if (key.startsWith('radio_snapshot:')) {
    final data = jsonDecode(value);
    if (data is! Map || utf8.encode(value).length > 8 * 1024 * 1024) {
      throw const FormatException('广播快照无效');
    }
    final subscription = RadioSubscription(
      name: 'snapshot',
      url: Uri.parse(key.substring('radio_snapshot:'.length)),
    );
    RadioSnapshot.fromJson(data).stations(subscription);
    return true;
  }
  return false;
}
