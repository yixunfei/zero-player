import 'dart:convert';
import '../../../core/text/display_text.dart';
import '../domain/music_recommendation.dart';
import 'music_catalog_api.dart';

const musicHomepages = {
  'qqHome': 'QQ 音乐热歌',
  'home': '网易云新歌',
  'appleHome': 'Apple Music 中国区',
};

Uri musicDiscoveryUri(String value, Uri netease) => switch (value) {
  'qqHome' => Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
    'data': jsonEncode({
      'comm': {'ct': 24},
      'req': {
        'module': 'musicToplist.ToplistInfoServer',
        'method': 'GetDetail',
        'param': {'topid': 26, 'offset': 0, 'num': 30},
      },
    }),
  }),
  'appleHome' => Uri.https(
    'rss.marketingtools.apple.com',
    '/api/v2/cn/music/most-played/50/songs.json',
  ),
  _ => netease.resolve('/api/personalized/newsong'),
};

/// Resize only known public artwork CDNs; other URLs keep their identity.
String musicThumbnail(String value) {
  final uri = Uri.tryParse(value.replaceFirst('http://', 'https://'));
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return '';
  }
  if (uri.host.endsWith('.music.126.net')) {
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'param': '300y300'})
        .toString();
  }
  if (uri.host.endsWith('.mzstatic.com')) {
    return uri
        .replace(
          path: uri.path.replaceFirst(RegExp(r'/\d+x\d+bb\.'), '/300x300bb.'),
        )
        .toString();
  }
  return uri.toString();
}

List<MusicRecommendation> parseQqHomepage(Object? raw) =>
    parseQqHomepagePage(raw).items;

MusicCatalogPage<MusicRecommendation> parseQqHomepagePage(Object? raw) {
  final req = raw is Map ? raw['req'] : null;
  final data = req is Map ? req['data'] : null;
  if (raw is! Map ||
      raw['code'] != 0 ||
      req is! Map ||
      req['code'] != 0 ||
      data is! Map ||
      data['songInfoList'] is! List) {
    throw const FormatException('QQ 音乐推荐暂不可用');
  }
  final rows = data['songInfoList'] as List;
  final details = data['data'];
  final total = musicCatalogCount(details is Map ? details['totalNum'] : null);
  return (
    items: parseQqChartSongs(rows, chart: details),
    total: total,
    next: musicCatalogNext(0, rows.length, 30, total),
  );
}

List<MusicRecommendation> parseQqChartSongs(List rows, {Object? chart}) {
  final ranks = chart is Map ? chart['song'] : null;
  final byId = <String, int>{
    if (ranks is List)
      for (final row in ranks.whereType<Map>())
        if (musicCatalogCount(row['rank']) case final rank? when rank > 0)
          '${row['songId']}': rank,
  };
  return [
    for (final row in rows.whereType<Map>())
      if (musicCatalogLabel(row['title'] ?? row['name']) case final title
          when title.isNotEmpty)
        MusicRecommendation(
          title,
          row['singer'] is List
              ? (row['singer'] as List)
                    .whereType<Map>()
                    .take(20)
                    .map((s) => musicCatalogLabel(s['name']))
                    .where((s) => s.isNotEmpty)
                    .join(' / ')
              : '',
          _qqCover(row['album']),
          description: row['album'] is Map
              ? musicCatalogLabel((row['album'] as Map)['name'])
              : '',
          id: musicCatalogId.hasMatch('${row['id']}') ? '${row['id']}' : '',
          rank: byId['${row['id']}'],
        ),
  ];
}

List<MusicRecommendation> parseNeteaseChartSongs(
  List rows, {
  Map<String, int> ranks = const {},
}) => [
  for (final row in rows.whereType<Map>())
    if (musicCatalogLabel(row['name']) case final title when title.isNotEmpty)
      MusicRecommendation(
        title,
        switch (row['artists'] ?? row['ar']) {
          final List artists =>
            artists
                .whereType<Map>()
                .take(20)
                .map((a) => musicCatalogLabel(a['name']))
                .where((name) => name.isNotEmpty)
                .join(' / '),
          _ => '',
        },
        musicThumbnail(switch (row['album'] ?? row['al']) {
          final Map album => '${album['picUrl'] ?? ''}',
          _ => '',
        }),
        description: switch (row['album'] ?? row['al']) {
          final Map album => musicCatalogLabel(album['name']),
          _ => '',
        },
        id: musicCatalogId.hasMatch('${row['id']}') ? '${row['id']}' : '',
        rank: ranks['${row['id']}'],
      ),
];

String _qqCover(Object? album) {
  final mid = album is Map ? album['mid'] : null;
  return mid is String && RegExp(r'^[A-Za-z0-9]+$').hasMatch(mid)
      ? 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$mid.jpg'
      : '';
}

List<MusicRecommendation> parseAppleHomepage(Object? raw) {
  final feed = raw is Map ? raw['feed'] : null;
  if (feed is! Map || feed['results'] is! List) {
    throw const FormatException('Apple Music 推荐暂不可用');
  }
  return [
    for (final row in (feed['results'] as List).take(50).whereType<Map>())
      if (row['name'] is String &&
          (row['name'] as String).trim().isNotEmpty &&
          row['contentAdvisoryRating'] != 'Explicit')
        MusicRecommendation(
          displayText(row['name'] as String),
          displayText('${row['artistName'] ?? ''}'),
          musicThumbnail('${row['artworkUrl100'] ?? ''}'),
          description: 'Apple Music 中国区热门歌曲',
        ),
  ];
}
