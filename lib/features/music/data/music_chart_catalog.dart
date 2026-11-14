import 'package:html/parser.dart' as html;

import '../../../core/network/cancellation_token.dart';
import '../domain/music_recommendation.dart';
import 'music_catalog_api.dart';
import 'music_discovery_sources.dart';
import 'netease_music_details.dart';

typedef MusicChartSongs =
    Future<MusicCatalogPage<MusicRecommendation>> Function(
      int offset,
      CancellationToken token,
    );

/// Source-side chart header shown above the song list.
final class MusicChartInfo {
  const MusicChartInfo({
    this.title = '',
    this.updateTime = '',
    this.period = '',
    this.updateTips = '',
    this.listenNum,
    this.totalNum,
  });
  final String title, updateTime, period, updateTips;
  final int? listenNum, totalNum;

  static MusicChartInfo? parse(Object? raw) {
    if (raw is! Map) return null;
    final info = MusicChartInfo(
      title: musicCatalogLabel(raw['title']),
      updateTime: musicCatalogLabel(raw['updateTime']),
      period: musicCatalogLabel(raw['period']),
      updateTips: musicCatalogLabel(raw['updateTips']),
      listenNum: musicCatalogCount(raw['listenNum']),
      totalNum: musicCatalogCount(raw['totalNum']),
    );
    return info.title.isEmpty &&
            info.updateTime.isEmpty &&
            info.listenNum == null &&
            info.totalNum == null
        ? null
        : info;
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'updateTime': updateTime,
    'period': period,
    'updateTips': updateTips,
    if (listenNum != null) 'listenNum': listenNum,
    if (totalNum != null) 'totalNum': totalNum,
  };
  factory MusicChartInfo.fromJson(Map row) => MusicChartInfo(
    title: musicCatalogLabel(row['title']),
    updateTime: musicCatalogLabel(row['updateTime']),
    period: musicCatalogLabel(row['period']),
    updateTips: musicCatalogLabel(row['updateTips']),
    listenNum: musicCatalogCount(row['listenNum']),
    totalNum: musicCatalogCount(row['totalNum']),
  );
}

/// Callable page reader that can serve a prefetched first page and keeps the
/// latest chart header for the UI.
final class QqChartReader {
  QqChartReader(this._catalog, this.id, {this.first, this.info});
  final MusicChartCatalog _catalog;
  final String id;
  final MusicCatalogPage<MusicRecommendation>? first;
  MusicChartInfo? info;

  Future<MusicCatalogPage<MusicRecommendation>> call(
    int offset,
    CancellationToken token,
  ) {
    final prefetched = first;
    if (offset == 0 && prefetched != null) return Future.value(prefetched);
    return _catalog.qqSongs(id, offset, token, onInfo: (value) => info = value);
  }
}

final class MusicChartCatalog {
  MusicChartCatalog(this.api);
  final MusicCatalogApi api;
  late final _netease = NeteaseMusicDetails(api.network, endpoint: api.netease);
  static const _qqModule = 'musicToplist.ToplistInfoServer';
  static const qqPageSize = 30;

  /// Hot songs chart; stable id used to prefetch the first page with GetAll.
  static const qqDefaultId = '26';

  Future<List<MusicCatalogOption>> charts(
    String provider,
    CancellationToken token,
  ) async {
    final options = switch (provider) {
      'neteasePlaylist' => await _neteaseCharts(token),
      'qqPlaylist' => await _qqCharts(token),
      'kugouPlaylist' => await _kugouCharts(token),
      _ => throw const FormatException('未知榜单平台'),
    };
    if (options.isEmpty) throw const FormatException('平台未返回公开榜单');
    return {for (final option in options) option.id: option}.values.toList();
  }

  Future<List<MusicCatalogOption>> _neteaseCharts(
    CancellationToken token,
  ) async {
    final uri = api.netease.resolve('/discover/toplist');
    final doc = await api.get(uri, token);
    return [
      for (final group
          in html.parse(doc.text).querySelectorAll('.n-minelst h2'))
        if (group.nextElementSibling?.localName == 'ul')
          for (final link in group.nextElementSibling!.querySelectorAll(
            'p.name > a',
          ))
            ?_option(
              Uri.tryParse(
                link.attributes['href'] ?? '',
              )?.queryParameters['id'],
              link.text,
              group.text,
            ),
    ];
  }

  Future<List<MusicCatalogOption>> _qqCharts(CancellationToken token) async =>
      _parseQqCharts(await api.qqRequest(_qqModule, 'GetAll', {}, token));

  List<MusicCatalogOption> _parseQqCharts(Map data) => [
    for (final group in musicCatalogRows(data['group']).whereType<Map>())
      for (final row in musicCatalogRows(group['toplist']).whereType<Map>())
        ?_option(row['topId'], row['title'], group['groupName']),
  ];

  /// Directory plus the selected chart's first page in one QQ round trip.
  Future<
    ({
      List<MusicCatalogOption> options,
      MusicCatalogOption selected,
      QqChartReader? reader,
    })
  >
  qqDirectory(String? preferredId, CancellationToken token) async {
    final target = preferredId ?? qqDefaultId;
    List<Map> responses;
    try {
      responses = await api.qqBatch([
        (module: _qqModule, method: 'GetAll', params: const {}),
        (
          module: _qqModule,
          method: 'GetDetail',
          params: {'topid': int.parse(target), 'offset': 0, 'num': qqPageSize},
        ),
      ], token);
    } catch (_) {
      token.check();
      final options = await _qqCharts(token);
      if (options.isEmpty) throw const FormatException('平台未返回公开榜单');
      return (
        options: options,
        selected: options.firstWhere(
          (option) => option.id == target,
          orElse: () => options.first,
        ),
        reader: null,
      );
    }
    final options = _parseQqCharts(responses[0]);
    if (options.isEmpty) throw const FormatException('平台未返回公开榜单');
    final selected =
        options.where((option) => option.id == target).firstOrNull ??
        options.first;
    final first = _qqPage(responses[1]);
    return (
      options: options,
      selected: selected,
      reader: selected.id == target
          ? QqChartReader(
              this,
              selected.id,
              first: first.page,
              info: first.info,
            )
          : null,
    );
  }

  Future<List<MusicCatalogOption>> _kugouCharts(CancellationToken token) async {
    final doc = await api.get(
      api.kugouWeb.resolve('/yy/html/rank.html'),
      token,
    );
    return [
      for (final group
          in html.parse(doc.text).querySelectorAll('.pc_rank_sidebar'))
        for (final link in group.querySelectorAll('ul a[href]'))
          ?_option(
            RegExp(r'^/yy/rank/home/1-(\d+)\.html$').firstMatch(
              Uri.tryParse(link.attributes['href']!)?.path ?? '',
            )?[1],
            link.attributes['title'] ?? link.text,
            group.querySelector('h3')?.text,
          ),
    ];
  }

  MusicCatalogOption? _option(Object? value, Object? title, Object? section) {
    final id = '$value';
    final name = musicCatalogLabel(title);
    final group = musicCatalogLabel(section);
    return musicCatalogId.hasMatch(id) && name.isNotEmpty && group.isNotEmpty
        ? (id: id, name: name, group: group)
        : null;
  }

  Uri uri(String provider, String id) => switch (provider) {
    'qqPlaylist' => Uri.https('y.qq.com', '/n/ryqq_v2/toplist/$id'),
    'kugouPlaylist' => Uri.https('www.kugou.com', '/yy/rank/home/1-$id.html'),
    _ => Uri.https('music.163.com', '/discover/toplist', {'id': id}),
  };

  Future<MusicChartSongs> open(
    String provider,
    String id,
    CancellationToken token,
  ) async {
    if (!musicCatalogId.hasMatch(id) || int.tryParse(id) == null) {
      throw const FormatException('榜单标识无效');
    }
    switch (provider) {
      case 'qqPlaylist':
        return QqChartReader(this, id).call;
      case 'kugouPlaylist':
        return (offset, token) => _kugouSongs(id, offset, token);
      case 'neteasePlaylist':
        final list = await _netease.openPlaylist(id, token);
        return (offset, token) async {
          final page = await list.rows(offset, 50, token);
          return (
            items: parseNeteaseChartSongs(
              page.items,
              ranks: list.ranks(offset, 50),
            ),
            total: page.total,
            next: page.next,
          );
        };
      default:
        throw const FormatException('未知榜单平台');
    }
  }

  Future<MusicCatalogPage<MusicRecommendation>> qqSongs(
    String id,
    int offset,
    CancellationToken token, {
    void Function(MusicChartInfo)? onInfo,
  }) async {
    final data = await api.qqRequest(_qqModule, 'GetDetail', {
      'topid': int.parse(id),
      'offset': offset,
      'num': qqPageSize,
    }, token);
    final result = _qqPage(data, offset);
    if (result.info case final info?) onInfo?.call(info);
    return result.page;
  }

  ({MusicCatalogPage<MusicRecommendation> page, MusicChartInfo? info}) _qqPage(
    Map data, [
    int offset = 0,
  ]) {
    final rows = musicCatalogRows(data['songInfoList']);
    final raw = data['data'];
    final info = MusicChartInfo.parse(raw);
    final total =
        info?.totalNum ??
        musicCatalogCount(raw is Map ? raw['totalNum'] : null);
    return (
      page: (
        items: parseQqChartSongs(rows, chart: raw),
        total: total,
        next: musicCatalogNext(offset, rows.length, qqPageSize, total),
      ),
      info: info,
    );
  }

  Future<MusicCatalogPage<MusicRecommendation>> _kugouSongs(
    String id,
    int cursor,
    CancellationToken token,
  ) async {
    final page = cursor + 1;
    final doc = await api.get(
      api.kugouWeb.resolve('/yy/rank/home/$page-$id.html'),
      token,
    );
    final tree = html.parse(doc.text);
    final list = tree.querySelector('.pc_temp_songlist');
    if (list == null) throw const FormatException('酷狗榜单曲目暂不可用');
    final rows = list.querySelectorAll('a.pc_temp_songname');
    final items = <MusicRecommendation>[];
    for (final row in rows) {
      final artist = musicCatalogLabel(
        row.querySelector('span')?.text,
      ).replaceFirst(RegExp(r'^\s*-\s*'), '');
      final title = musicCatalogLabel(
        row.nodes.where((n) => n.nodeType == 3).map((node) => node.text).join(),
      );
      if (title.isNotEmpty) {
        final id = row.parent?.attributes['data-eid'] ?? '';
        final rank = musicCatalogCount(
          row.parent?.querySelector('.pc_temp_num')?.text.trim(),
        );
        items.add(
          MusicRecommendation(
            title,
            artist,
            '',
            id: RegExp(r'^[a-zA-Z0-9]{1,32}$').hasMatch(id) ? id : '',
            rank: rank == 0 ? null : rank,
          ),
        );
      }
    }
    int? metadata(String field) => musicCatalogCount(
      RegExp(
        "^[ \t]*$field:[ \t]*'(\\d+)'",
        multiLine: true,
      ).firstMatch(doc.text)?[1],
    );
    final total = metadata('total');
    final size = metadata('pagesize') ?? 22;
    final currentPage = metadata('page');
    if (currentPage != null && currentPage != page) {
      throw const FormatException('酷狗返回了不同的榜单页');
    }
    final next =
        rows.isNotEmpty &&
            (total == null ? rows.length >= size : page * size < total)
        ? page
        : null;
    return (items: items, total: total, next: next);
  }
}
