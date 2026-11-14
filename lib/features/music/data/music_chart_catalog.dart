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

final class MusicChartCatalog {
  MusicChartCatalog(this.api);
  final MusicCatalogApi api;
  late final _netease = NeteaseMusicDetails(api.network, endpoint: api.netease);
  static const _qqModule = 'musicToplist.ToplistInfoServer';

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

  Future<List<MusicCatalogOption>> _qqCharts(CancellationToken token) async {
    final data = await api.qqRequest(_qqModule, 'GetAll', {}, token);
    return [
      for (final group in musicCatalogRows(data['group']).whereType<Map>())
        for (final row in musicCatalogRows(group['toplist']).whereType<Map>())
          ?_option(row['topId'], row['title'], group['groupName']),
    ];
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
        return (offset, token) => qqSongs(id, offset, token);
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
    CancellationToken token,
  ) async {
    const size = 30;
    final data = await api.qqRequest(_qqModule, 'GetDetail', {
      'topid': int.parse(id),
      'offset': offset,
      'num': size,
    }, token);
    final rows = musicCatalogRows(data['songInfoList']);
    final info = data['data'];
    final total = musicCatalogCount(info is Map ? info['totalNum'] : null);
    return (
      items: parseQqChartSongs(rows, chart: info),
      total: total,
      next: musicCatalogNext(offset, rows.length, size, total),
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
