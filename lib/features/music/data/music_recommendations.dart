import 'dart:convert';
import 'dart:async';
import 'music_collections.dart';
import 'music_discovery_sources.dart';
export 'music_discovery_sources.dart' show musicHomepages;
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

/// Public homepage discovery metadata. Playback remains with the chosen source.
List<MusicRecommendation> parseHomepageSongs(Object? raw) {
  if (raw is! Map || raw['code'] != 200 || raw['result'] is! List) {
    throw const FormatException('首页推荐数据暂不可用');
  }
  return [
    for (final entry in (raw['result'] as List).take(80))
      if (entry is Map && entry['song'] is Map)
        MusicRecommendation(
          displayText('${entry['name'] ?? ''}'),
          _rows((entry['song'] as Map)['artists'])
              .whereType<Map>()
              .map((artist) => displayText('${artist['name'] ?? ''}'))
              .join(' / '),
          musicThumbnail('${entry['picUrl'] ?? ''}'),
          description: _albumName((entry['song'] as Map)['album']),
        ),
  ].where((item) => item.title.isNotEmpty).toList();
}

Iterable<Map> _rows(Object? value) =>
    value is List ? value.whereType<Map>() : const <Map>[];

String _albumName(Object? value) =>
    value is Map ? displayText('${value['name'] ?? ''}') : '';

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
    for (final row in (list['tracks'] as List).take(80).whereType<Map>())
      MusicRecommendation(
        displayText('${row['name'] ?? ''}'),
        _rows(
          row['artists'] ?? row['ar'],
        ).map((a) => displayText('${a['name'] ?? ''}')).join(' / '),
        musicThumbnail(
          '${(row['album'] ?? row['al'] as Object?) is Map ? ((row['album'] ?? row['al']) as Map)['picUrl'] ?? '' : ''}',
        ),
        description: _albumName(row['album'] ?? row['al']),
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
  MusicRecommendations(
    this.network,
    this.db, {
    Uri? endpoint,
    this.requestTimeout = const Duration(seconds: 6),
    this.homeEndpoints = const {},
  }) : endpoint = endpoint ?? Uri.parse('https://music.163.com');
  final DocumentClient network;
  final AppDatabase db;
  final Uri endpoint;
  final Duration requestTimeout;
  final Map<String, Uri> homeEndpoints;
  final _memory = <String, ({int time, List<MusicRecommendation> items})>{};
  Future<void>? _initial;
  Future<void> _writes = Future.value();
  List<MusicRecommendation> items = [];
  String chart = 'qqHome';
  String homepage = 'qqHome';
  String get category => musicHomepages.containsKey(chart)
      ? '推荐'
      : musicCollections[chart]?.category ?? '榜单';
  bool loading = false;
  bool showingFallback = false;
  String? notice;
  CancellationToken? _request;
  bool _closed = false;

  Future<void> initialize() => _initial ??= _restoreHomepage();
  Future<void> _restoreHomepage() async {
    try {
      final rows = await db.rows(
        "SELECT value FROM app_meta WHERE key='music_discovery_homepage'",
      );
      if (_closed || _request != null) return;
      if (rows.isNotEmpty && musicHomepages.containsKey(rows.first['value'])) {
        homepage = rows.first['value'] as String;
      }
    } catch (_) {
      // Local preference failure must not prevent browsing.
    }
    if (!_closed && _request == null) await load(homepage);
  }

  Future<void> load(String value, {bool refresh = false}) async {
    if (_closed ||
        !(musicHomepages.containsKey(value) ||
            musicCharts.containsKey(value) ||
            musicCollections.containsKey(value))) {
      return;
    }
    if (loading && chart == value && !refresh) return;
    _request?.cancel();
    final token = _request = CancellationToken();
    final previous = chart;
    chart = value;
    loading = true;
    notice = null;
    if (previous != value) {
      items = [];
      showingFallback = false;
    }
    if (musicHomepages.containsKey(value)) {
      homepage = value;
      _writes = _writes
          .then(
            (_) => db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
              'music_discovery_homepage',
              value,
            ]),
          )
          .catchError((Object _) {
            if (!_closed && chart == value) {
              notice = '发现来源未能保存，本次仍可浏览。';
              notifyListeners();
            }
          });
    }
    final collection = musicCollections[value];
    if (collection != null) {
      items = collection.songs;
      showingFallback = false;
      loading = false;
      notice = '${collection.description} 编辑精选歌单 · 点击歌曲搜索，播放可用性以渠道为准。';
      notifyListeners();
      return;
    }
    notifyListeners();
    try {
      final saved = _memory[value] ?? await _readCache(value);
      token.check();
      if (saved != null && saved.items.isNotEmpty) {
        items = saved.items;
        showingFallback = false;
        final age = DateTime.now().millisecondsSinceEpoch - saved.time;
        if (!refresh && age >= 0 && age < 3600000) return;
      }
      if (items.isEmpty) {
        items = musicCollections['mandarin']!.songs;
        showingFallback = true;
        notice = '推荐加载中，可以先听编辑精选，或切换发现来源。';
      }
      notifyListeners();
      final result = await _fetch(value, token);
      token.check();
      if (result.isEmpty) throw const FormatException('没有可显示的推荐音乐');
      items = result;
      showingFallback = false;
      notice = null;
      await _saveCache(value, result);
    } catch (_) {
      if (!_closed && !token.isCancelled) {
        notice = showingFallback
            ? '当前来源暂不可用，先浏览编辑精选；可切换来源或重试。'
            : '推荐更新失败，正在显示本机缓存。';
      }
    } finally {
      if (!_closed && !token.isCancelled) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<({int time, List<MusicRecommendation> items})?> _readCache(
    String value,
  ) async {
    try {
      final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
        'music_recommendation:$value',
      ]);
      if (rows.isEmpty) return null;
      final saved = jsonDecode(rows.first['value'] as String) as Map;
      return _memory[value] = (
        time: saved['time'] as int,
        items: (saved['items'] as List)
            .take(80)
            .cast<Map>()
            .map(MusicRecommendation.fromJson)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<MusicRecommendation>> _fetch(
    String value,
    CancellationToken token,
  ) async {
    final request = CancellationToken();
    final unlink = token.listen(request.cancel);
    try {
      final uri = musicHomepages.containsKey(value)
          ? homeEndpoints[value] ?? musicDiscoveryUri(value, endpoint)
          : value == 'wfu'
          ? Uri.parse('https://music1.wfuapp.com/')
          : endpoint
                .resolve('/api/playlist/detail')
                .replace(queryParameters: {'id': _chartIds[value]!});
      final doc = await network
          .get(
            uri,
            headers: {
              'Accept-Encoding': 'gzip',
              if (value == 'qqHome') 'Referer': 'https://y.qq.com/',
            },
            cancellation: request,
            maxBytes: 2 * 1024 * 1024,
            networkTimeout: requestTimeout,
          )
          .timeout(
            requestTimeout,
            onTimeout: () {
              request.cancel();
              throw TimeoutException('推荐请求超时');
            },
          );
      token.check();
      return switch (value) {
        'qqHome' => parseQqHomepage(doc.json),
        'appleHome' => parseAppleHomepage(doc.json),
        'home' => parseHomepageSongs(doc.json),
        'wfu' => parseWfuRecommendations(doc.text),
        _ => parseMusicRecommendations(doc.json),
      };
    } finally {
      unlink();
      request.cancel();
    }
  }

  Future<void> _saveCache(
    String value,
    List<MusicRecommendation> result,
  ) async {
    final saved = (time: DateTime.now().millisecondsSinceEpoch, items: result);
    _memory[value] = saved;
    _writes = _writes
        .then(
          (_) => db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
            'music_recommendation:$value',
            jsonEncode({
              'time': saved.time,
              'items': result.map((i) => i.toJson()).toList(),
            }),
          ]),
        )
        .catchError((Object _) {
          if (!_closed && chart == value) notice = '推荐已更新，本机缓存未能保存。';
        });
    await _writes;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _request?.cancel();
    super.dispose();
    await _initial;
    await _writes;
  }
}
