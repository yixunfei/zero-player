import 'dart:convert';
import '../../../core/text/display_text.dart';
import '../domain/music_recommendation.dart';

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
  if (uri == null || uri.scheme != 'https') return '';
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

List<MusicRecommendation> parseQqHomepage(Object? raw) {
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
  return [
    for (final row in (data['songInfoList'] as List).take(50).whereType<Map>())
      if (row['name'] is String && (row['name'] as String).trim().isNotEmpty)
        MusicRecommendation(
          displayText(row['name'] as String),
          row['singer'] is List
              ? (row['singer'] as List)
                    .whereType<Map>()
                    .map((s) => displayText('${s['name'] ?? ''}'))
                    .join(' / ')
              : '',
          _qqCover(row['album']),
          description: row['album'] is Map
              ? displayText('${(row['album'] as Map)['name'] ?? ''}')
              : '',
        ),
  ];
}

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
