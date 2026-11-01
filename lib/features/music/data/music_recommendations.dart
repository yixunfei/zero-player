import 'dart:convert';
import 'music_collections.dart';
import '../domain/music_recommendation.dart';
export '../domain/music_recommendation.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/persistence/app_database.dart';
import '../../../core/text/display_text.dart';

const musicCharts = {
  'hot': '热歌榜',
  'new': '新歌榜',
  'original': '原创榜',
  'rising': '飙升榜',
  'wfu': 'WFU 音乐精选',
};
const _chartIds = {
  'hot': '3778678',
  'new': '3779629',
  'original': '2884035',
  'rising': '19723756',
};

List<MusicRecommendation> parseMusicRecommendations(Object? raw) {
  if (raw is! Map || raw['code'] != 200) {
    throw const FormatException('推荐音乐数据暂不可用');
  }
  final list = raw['result'] ?? raw['playlist'];
  if (list is! Map || list['tracks'] is! List) {
    throw const FormatException('推荐音乐列表格式已变更');
  }
  return [
    for (final row in (list['tracks'] as List).take(80).cast<Map>())
      MusicRecommendation(
        displayText('${row['name'] ?? ''}'),
        ((row['artists'] ?? row['ar']) as List? ?? [])
            .cast<Map>()
            .map((a) => displayText('${a['name'] ?? ''}'))
            .join(' / '),
        '${(row['album'] ?? row['al'] as Object?) is Map ? ((row['album'] ?? row['al']) as Map)['picUrl'] ?? '' : ''}'
            .replaceFirst('http://', 'https://'),
        description: '${((row['album'] ?? row['al']) as Map?)?['name'] ?? ''}',
      ),
  ].where((item) => item.title.isNotEmpty).toList();
}

List<MusicRecommendation> parseWfuRecommendations(String body) {
  final document = html.parse(body);
  return [
    for (final row
        in document
            .querySelectorAll(
              '.channel-group li[data-id], .channel-group li[data-list]',
            )
            .take(80))
      MusicRecommendation(
        displayText(row.text).replaceAll(RegExp(r'[（(]直播[）)]'), ''),
        '',
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(row.attributes['data-id'] ?? '')
            ? 'https://i.ytimg.com/vi/${row.attributes['data-id']}/hqdefault.jpg'
            : '',
        description: 'WFU 音乐主题，点击后通过所选渠道搜索；不提取 YouTube 嵌入播放地址。',
      ),
  ].where((item) => item.title.isNotEmpty).toList();
}

final class MusicRecommendations extends ChangeNotifier {
  MusicRecommendations(this.network, this.db, {Uri? endpoint})
    : endpoint = endpoint ?? Uri.parse('https://music.163.com');
  final DocumentClient network;
  final AppDatabase db;
  final Uri endpoint;
  List<MusicRecommendation> items = [];
  String chart = 'hot';
  String get category => musicCollections[chart]?.category ?? '榜单';
  bool loading = false;
  String? notice;
  CancellationToken? _request;
  bool _closed = false;
  Future<void> load(String value, {bool refresh = false}) async {
    if (_closed ||
        (!musicCharts.containsKey(value) &&
            !musicCollections.containsKey(value))) {
      return;
    }
    if (loading && chart == value && !refresh) return;
    _request?.cancel();
    final token = _request = CancellationToken();
    final previous = chart;
    chart = value;
    loading = true;
    notice = null;
    if (previous != value) items = [];
    final collection = musicCollections[value];
    if (collection != null) {
      items = collection.songs;
      loading = false;
      notice = '${collection.description} 编辑精选歌单 · 点击歌曲搜索，播放可用性以渠道为准。';
      notifyListeners();
      return;
    }
    notifyListeners();
    try {
      final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
        'music_recommendation:$value',
      ]);
      token.check();
      if (rows.isNotEmpty) {
        try {
          final saved = jsonDecode(rows.first['value'] as String) as Map;
          final age =
              DateTime.now().millisecondsSinceEpoch - (saved['time'] as int);
          items = (saved['items'] as List)
              .take(80)
              .cast<Map>()
              .map(MusicRecommendation.fromJson)
              .toList();
          if (!refresh && items.isNotEmpty && age >= 0 && age < 3600000) return;
        } on FormatException {
          items = [];
        } on TypeError {
          items = [];
        }
      }
      token.check();
      if (items.isNotEmpty) notifyListeners();
      final doc = await network.get(
        value == 'wfu'
            ? Uri.parse('https://music1.wfuapp.com/')
            : endpoint
                  .resolve('/api/playlist/detail')
                  .replace(queryParameters: {'id': _chartIds[value]!}),
        cancellation: token,
        maxBytes: 4 * 1024 * 1024,
      );
      final result = value == 'wfu'
          ? parseWfuRecommendations(doc.text)
          : parseMusicRecommendations(doc.json);
      token.check();
      if (result.isEmpty) throw const FormatException('没有可显示的推荐音乐');
      items = result;
      await db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
        'music_recommendation:$value',
        jsonEncode({
          'time': DateTime.now().millisecondsSinceEpoch,
          'items': items.map((i) => i.toJson()).toList(),
        }),
      ]);
    } catch (_) {
      if (!_closed && !token.isCancelled) {
        notice = items.isEmpty ? '推荐音乐暂不可用，请重试或直接搜索。' : '推荐更新失败，正在显示本机缓存。';
      }
    } finally {
      if (!_closed && !token.isCancelled) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void close() {
    _closed = true;
    _request?.cancel();
    super.dispose();
  }
}
