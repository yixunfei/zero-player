import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/network_target_policy.dart';
import '../../../core/text/display_text.dart';
import '../domain/music_track.dart';

final class WebsiteMusicSources {
  WebsiteMusicSources(this.network, {Uri? qqEndpoint, Uri? boxEndpoint})
    : qqEndpoint = qqEndpoint ?? Uri.parse('https://www.qqmp3.vip'),
      boxEndpoint =
          boxEndpoint ?? Uri.parse('https://fy-musicbox-api.mu-jie.cc');
  final DocumentClient network;
  final Uri qqEndpoint, boxEndpoint;
  static Map<String, String> headers(String provider) => {
    'User-Agent': 'Mozilla/5.0',
    'Referer': provider == 'qqmp3'
        ? 'https://www.qqmp3.vip/'
        : 'https://mu-jie.cc/musicBox/',
    if (provider == 'musicBox') 'Origin': 'https://mu-jie.cc',
    if (provider == 'qqmp3') 'X-Requested-With': 'XMLHttpRequest',
  };
  Future<MusicSearchResult> search(
    String provider,
    String query,
    int page,
    CancellationToken? token,
  ) async {
    final qq = provider == 'qqmp3' || provider == 'lxGrass';
    final uri = qq
        ? qqEndpoint
              .resolve('/api/songs.php')
              .replace(queryParameters: {'type': 'search', 'keyword': query})
        : boxEndpoint
              .resolve('/netease/search/song/')
              .replace(
                queryParameters: {
                  'keywords': query,
                  'pn': '$page',
                  'limit': '30',
                },
              );
    final raw = (await network.get(
      uri,
      headers: headers(qq ? 'qqmp3' : provider),
      cancellation: token,
    )).json;
    if (qq && (raw is! Map || raw['code'] != 200 || raw['data'] is! List)) {
      throw const FormatException('米兔音乐没有返回有效歌曲列表');
    }
    final rows = qq ? (raw as Map)['data'] as List : raw as List;
    final slice = qq ? rows.skip((page - 1) * 30).take(30) : rows.take(30);
    final tracks = <MusicTrack>[];
    for (final row in slice.cast<Map>()) {
      final id = '${row[qq ? 'rid' : 'id']}';
      if (!RegExp(r'^\d+$').hasMatch(id)) continue;
      final title = displayText('${row['name'] ?? ''}');
      if (title.isEmpty) continue;
      tracks.add(
        MusicTrack(
          id: id,
          title: title,
          artist: displayText('${row['artist'] ?? ''}'),
          url: qq
              ? qqEndpoint
                    .resolve('/api/kw.php')
                    .replace(queryParameters: {'rid': id})
              : boxEndpoint
                    .resolve('/meting/')
                    .replace(
                      queryParameters: {
                        'server': 'netease',
                        'type': 'url',
                        'id': id,
                      },
                    ),
          fetchedAt: DateTime.now(),
          provider: provider,
          query: query,
          page: page,
          downloadable: !qq,
          cover: '${row['pic'] ?? ''}',
        ),
      );
    }
    return MusicSearchResult(
      List.unmodifiable(tracks),
      hasNext: qq ? rows.length > page * 30 : rows.length == 30,
    );
  }

  Future<MusicTrack> resolve(MusicTrack track, CancellationToken token) async {
    if (!RegExp(r'^\d+$').hasMatch(track.id)) {
      throw const FormatException('歌曲标识无效');
    }
    if (track.provider == 'musicBox') {
      return track.withUrl(
        boxEndpoint
            .resolve('/meting/')
            .replace(
              queryParameters: {
                'server': 'netease',
                'type': 'url',
                'id': track.id,
              },
            ),
      );
    }
    final doc = await network.get(
      qqEndpoint
          .resolve('/api/kw.php')
          .replace(
            queryParameters: {
              'rid': track.id,
              'type': 'json',
              'level': 'exhigh',
              'lrc': 'true',
            },
          ),
      headers: headers('qqmp3'),
      cancellation: token,
    );
    final data = doc.json as Map;
    final nested = data['data'];
    final raw =
        data['url'] ??
        (nested is Map
            ? (nested['url'] ?? nested['play_url'] ?? nested['playUrl'])
            : null);
    if (raw is! String) throw const FormatException('米兔音乐暂未返回播放地址');
    final uri = Uri.parse(raw);
    NetworkTargetPolicy.validateUri(uri);
    return track.withUrl(uri);
  }
}
