import 'live_channel.dart';
import 'channel_identity.dart';

int? cctvNumber(String name) => int.tryParse(
  RegExp(
        r'CCTV[\s\-]*([0-9]+)',
        caseSensitive: false,
      ).firstMatch(name)?.group(1) ??
      '',
);
String channelGroup(LiveChannel channel) {
  if (channel.urls.isEmpty) return '暂不可用';
  if (RegExp(r'CCTV|CGTN|中央|央视', caseSensitive: false).hasMatch(channel.name)) {
    return '央视';
  }
  if (channel.name.contains('卫视')) return '卫视';
  return channel.group.isEmpty ? '其他' : channel.group;
}

int compareChannels(LiveChannel a, LiveChannel b) {
  int rank(LiveChannel c) => switch (channelGroup(c)) {
    '央视' => 0,
    '卫视' => 1,
    _ => 2,
  };
  var result = rank(a).compareTo(rank(b));
  if (result != 0) return result;
  result = (cctvNumber(a.name) ?? 999).compareTo(cctvNumber(b.name) ?? 999);
  if (result != 0) return result;
  result = a.name.contains('+') == b.name.contains('+')
      ? 0
      : a.name.contains('+')
      ? 1
      : -1;
  if (result != 0) return result;
  result = a.name.compareTo(b.name);
  if (result != 0) return result;
  result = (a.health.latencyMs ?? 999999).compareTo(
    b.health.latencyMs ?? 999999,
  );
  return result != 0 ? result : a.listId.compareTo(b.listId);
}

bool matchesChannel(LiveChannel c, String group, String query) {
  if (!channelMatchesQuery(c.name, query) &&
      !c.entries.any((entry) => channelMatchesQuery(entry.name, query)) &&
      ![c.listName, ...c.categories, ...c.languages, ...c.resolutions].any(
        (text) => text.toLowerCase().contains(query.trim().toLowerCase()),
      )) {
    return false;
  }
  if (group == '已移除') return c.health.removed;
  if (c.health.removed) return false;
  if (group == '已停用') return !c.health.enabled;
  if (group == '待处理') {
    return {'unavailable', 'inconclusive'}.contains(c.health.availability.name);
  }
  if (!c.health.enabled) return false;
  return group == '全部' ||
      group == '收藏' && c.favorite ||
      group == '最近' && c.recent ||
      group == '未确定' && c.health.availability.name == 'inconclusive' ||
      group == '有媒体响应' && c.health.availability.name == 'responding' ||
      channelGroup(c) == group;
}
