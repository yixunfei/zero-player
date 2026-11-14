import 'dart:convert';
import 'dart:async';
import 'music_catalog_api.dart';
import 'music_chart_catalog.dart';
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
import '../../supervision/domain/supervision_rules.dart';

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
  return parseNeteaseChartSongs(list['tracks'] as List);
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
    MusicChartCatalog? chartCatalog,
    this.sourceAllowed,
    this.textAllowed,
  }) : endpoint = endpoint ?? Uri.https('music.163.com'),
       chartCatalog =
           chartCatalog ??
           MusicChartCatalog(MusicCatalogApi(network, netease: endpoint));
  final DocumentClient network;
  final AppDatabase db;
  final Uri endpoint;
  final Duration requestTimeout;
  final Map<String, Uri> homeEndpoints;
  final MusicChartCatalog chartCatalog;
  final bool Function(String provider)? sourceAllowed;
  final bool Function(String text)? textAllowed;
  final _memory =
      <String, ({int time, MusicCatalogPage<MusicRecommendation> page})>{};
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
  String? pageError;
  int? _next;
  int? total;
  bool get hasMore => _next != null;
  bool get visible => showingFallback || _allowed(chart);
  MusicChartSongs? _readPage;
  String chartPlatform = 'neteasePlaylist';
  final _directories = <String, List<MusicCatalogOption>>{};
  List<MusicCatalogOption> get charts => _sourceAllowed(chartPlatform)
      ? (_directories[chartPlatform] ?? [])
            .where(
              (item) => textAllowed?.call('${item.group} ${item.name}') ?? true,
            )
            .toList()
      : [];
  bool chartDirectoryLoading = false;
  String? chartDirectoryError;
  CancellationToken? _directoryRequest;
  CancellationToken? _request;
  bool _closed = false;

  Future<void> initialize() => _initial ??= _restoreHomepage();
  Future<void> _restoreHomepage() async {
    try {
      final rows = await db.rows(
        "SELECT value FROM app_meta WHERE key='music_discovery_homepage'",
      );
      if (_closed || _request != null || _directoryRequest != null) return;
      if (rows.isNotEmpty && musicHomepages.containsKey(rows.first['value'])) {
        homepage = rows.first['value'] as String;
      }
    } catch (_) {
      // Local preference failure must not prevent browsing.
    }
    if (!_closed && _request == null && _directoryRequest == null) {
      await load(homepage);
    }
  }

  Future<void> load(String value, {bool refresh = false}) async {
    if (_closed ||
        !(musicHomepages.containsKey(value) ||
            musicCharts.containsKey(value) ||
            musicCollections.containsKey(value) ||
            _chartFor(value) != null)) {
      return;
    }
    if (loading && chart == value && !refresh) return;
    _directoryRequest?.cancel();
    chartDirectoryLoading = false;
    _request?.cancel();
    final token = _request = CancellationToken();
    final previous = chart;
    chart = value;
    loading = true;
    notice = null;
    pageError = null;
    if (previous != value) {
      items = [];
      showingFallback = false;
      _next = total = null;
      _readPage = null;
    }
    if (musicHomepages.containsKey(value)) _rememberHomepage(value);
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
      if (!_allowed(value)) throw const ContentBlocked();
      final selected = _chartFor(value);
      final saved = selected == null
          ? _memory[value] ?? await _readCache(value)
          : null;
      token.check();
      if (saved != null && saved.page.items.isNotEmpty) {
        if (previous != value || items.isEmpty || showingFallback) {
          _setPage(saved.page);
        }
        final age = DateTime.now().millisecondsSinceEpoch - saved.time;
        if (!refresh && age >= 0 && age < 3600000) return;
      }
      if (items.isEmpty && musicHomepages.containsKey(value)) {
        items = musicCollections['mandarin']!.songs;
        showingFallback = true;
        notice = '推荐加载中，可以先听编辑精选，或切换发现来源。';
      }
      notifyListeners();
      final readPage = selected == null
          ? null
          : await chartCatalog.open(chartPlatform, selected.id, token);
      final result = readPage == null
          ? await _fetch(value, token)
          : await readPage(0, token);
      token.check();
      if (!_allowed(value)) throw const ContentBlocked();
      if (result.items.isEmpty && result.next == null) {
        throw const FormatException('没有可显示的推荐音乐');
      }
      _readPage = readPage;
      _setPage(result);
      if (selected == null) await _saveCache(value, result);
    } catch (failure) {
      if (!_closed && !token.isCancelled) {
        notice = failure is ContentBlocked
            ? '当前平台已被过滤'
            : showingFallback
            ? '当前来源暂不可用，先浏览编辑精选；可切换来源或重试。'
            : items.isEmpty
            ? '当前栏目暂不可用，请重试。'
            : _chartFor(value) == null
            ? '推荐更新失败，正在显示本机缓存。'
            : '榜单更新失败，已保留当前曲目。';
      }
    } finally {
      if (!_closed && !token.isCancelled) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _rememberHomepage(String value) {
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

  bool _sourceAllowed(String? provider) =>
      provider == null || (sourceAllowed?.call(provider) ?? true);
  bool _allowed(String value) =>
      _sourceAllowed(_providerFor(value)) &&
      (!value.startsWith('chart:') ||
          value.endsWith(':') ||
          _chartFor(value) != null);

  String? _providerFor(String value) => switch (value) {
    'qqHome' => 'qqPlaylist',
    'appleHome' => 'appleHome',
    'wfu' => 'wfu',
    'home' || 'hot' || 'new' || 'original' || 'rising' => 'neteasePlaylist',
    _ => value.startsWith('chart:') ? value.split(':')[1] : null,
  };

  MusicCatalogOption? _chartFor(String value) {
    for (final option in charts) {
      if (value == 'chart:$chartPlatform:${option.id}') return option;
    }
    return null;
  }

  MusicCatalogOption? get selectedChart => _chartFor(chart);
  Uri? get chartUri => selectedChart == null
      ? null
      : chartCatalog.uri(chartPlatform, selectedChart!.id);

  Future<void> selectChartPlatform(
    String provider, {
    bool refresh = false,
  }) async {
    if (_closed || !musicCatalogPlatforms.containsKey(provider)) return;
    if (chartDirectoryLoading && chartPlatform == provider && !refresh) return;
    _directoryRequest?.cancel();
    _request?.cancel();
    final token = _directoryRequest = CancellationToken();
    final previous = selectedChart?.id;
    chartPlatform = provider;
    chart = 'chart:$provider:';
    items = [];
    _next = total = null;
    _readPage = null;
    notice = pageError = chartDirectoryError = null;
    showingFallback = loading = false;
    chartDirectoryLoading = true;
    notifyListeners();
    try {
      if (!_sourceAllowed(provider)) throw const ContentBlocked();
      if (refresh || !_directories.containsKey(provider)) {
        final options = await chartCatalog.charts(provider, token);
        token.check();
        _directories[provider] = options;
      }
    } catch (failure) {
      if (!_closed && !token.isCancelled) {
        chartDirectoryError = failure is ContentBlocked
            ? '当前平台已被过滤'
            : '榜单目录暂不可用';
      }
    } finally {
      if (!_closed && !token.isCancelled) {
        chartDirectoryLoading = false;
        final options = charts;
        if (options.isNotEmpty) {
          await selectChart(
            options.firstWhere(
              (item) => item.id == previous,
              orElse: () => options.first,
            ),
          );
        } else {
          notifyListeners();
        }
      }
    }
  }

  Future<void> selectChart(MusicCatalogOption option) =>
      load('chart:$chartPlatform:${option.id}');

  void _setPage(MusicCatalogPage<MusicRecommendation> page) {
    items = page.items;
    _next = page.next;
    total = page.total;
    showingFallback = false;
    notice = null;
  }

  Future<void> loadMore() async {
    final cursor = _next;
    if (_closed || loading || cursor == null || !visible) return;
    final token = _request = CancellationToken();
    final readPage = _readPage;
    loading = true;
    pageError = null;
    notifyListeners();
    try {
      final page = await (readPage == null
          ? chartCatalog.qqSongs('26', cursor, token)
          : readPage(cursor, token));
      token.check();
      if (!visible) throw const ContentBlocked();
      Object key(MusicRecommendation item) =>
          item.id.isEmpty ? (item.title, item.artist) : item.id;
      final known = items.map(key).toSet();
      final added = page.items.where((item) => known.add(key(item))).toList();
      items = [...items, ...added];
      final next = page.next;
      _next =
          next != null &&
              next > cursor &&
              (added.isNotEmpty || page.items.isEmpty)
          ? next
          : null;
      total = page.total ?? total;
    } catch (failure) {
      if (!_closed && !token.isCancelled) {
        pageError = failure is ContentBlocked ? '当前平台已被过滤' : '下一页曲目加载失败';
      }
    } finally {
      if (!_closed && !token.isCancelled) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<({int time, MusicCatalogPage<MusicRecommendation> page})?> _readCache(
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
        page: (
          items: (saved['items'] as List)
              .take(80)
              .cast<Map>()
              .map(MusicRecommendation.fromJson)
              .toList(),
          next: value == 'qqHome' ? musicCatalogCount(saved['next']) : null,
          total: musicCatalogCount(saved['total']),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<MusicCatalogPage<MusicRecommendation>> _fetch(
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
      if (value == 'qqHome') return parseQqHomepagePage(doc.json);
      final items = switch (value) {
        'appleHome' => parseAppleHomepage(doc.json),
        'home' => parseHomepageSongs(doc.json),
        'wfu' => parseWfuRecommendations(doc.text),
        _ => parseMusicRecommendations(doc.json),
      };
      return (items: items, next: null, total: null);
    } finally {
      unlink();
      request.cancel();
    }
  }

  Future<void> _saveCache(
    String value,
    MusicCatalogPage<MusicRecommendation> page,
  ) async {
    final saved = (time: DateTime.now().millisecondsSinceEpoch, page: page);
    _memory[value] = saved;
    _writes = _writes
        .then(
          (_) => db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
            'music_recommendation:$value',
            jsonEncode({
              'time': saved.time,
              'items': page.items.map((i) => i.toJson()).toList(),
              'next': page.next,
              'total': page.total,
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
    _directoryRequest?.cancel();
    super.dispose();
    await _initial;
    await _writes;
  }
}
