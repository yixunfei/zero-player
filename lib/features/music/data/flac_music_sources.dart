import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/network_target_policy.dart';
import '../../../core/text/display_text.dart';
import '../domain/music_track.dart';

/// The site's anonymous Kuwo search and audition endpoints. Downloads are not used.
final class FlacMusicSources {
  FlacMusicSources(this.network, {Uri? endpoint})
    : endpoint = endpoint ?? Uri.parse('https://flac.music.hi.cn');

  final DocumentClient network;
  final Uri endpoint;
  static const _headers = {'Referer': 'https://flac.music.hi.cn/'};

  Future<Map> _searchRows(
    String query,
    int page,
    CancellationToken? token,
  ) async {
    final raw = (await network.postForm(
      endpoint.resolve('/ajax.php?act=search'),
      {'platform': 'kuwo', 'keyword': query, 'page': '$page', 'size': '20'},
      headers: _headers,
      cancellation: token,
    )).json;
    if (raw is! Map || raw['code'] != 0 || raw['data'] is! Map) {
      throw const FormatException('无损音乐搜索接口暂不可用');
    }
    final data = raw['data'] as Map;
    if (data['list'] is! List) {
      throw const FormatException('无损音乐搜索结果格式已变更');
    }
    return data;
  }

  Future<MusicSearchResult> search(
    String query,
    int page,
    CancellationToken? token,
  ) async {
    final data = await _searchRows(query, page, token);
    final tracks = <MusicTrack>[];
    for (final value in (data['list'] as List).take(20)) {
      if (value is! Map) continue;
      final id = '${value['id'] ?? ''}';
      final title = displayText('${value['name'] ?? ''}');
      if (!RegExp(r'^\d+$').hasMatch(id) || title.isEmpty) continue;
      final duration = int.tryParse('${value['duration'] ?? ''}') ?? 0;
      tracks.add(
        MusicTrack(
          id: id,
          title: title,
          artist: displayText('${value['artist'] ?? ''}'),
          url: endpoint.resolve('/ajax.php?act=getUrl'),
          duration: Duration(seconds: duration.clamp(0, 86400)),
          query: query,
          page: page,
          fetchedAt: DateTime.now(),
          provider: 'flacHi',
          downloadable: false,
          cover: '${value['pic_url'] ?? ''}',
        ),
      );
    }
    final total = int.tryParse('${data['total'] ?? ''}') ?? 0;
    return MusicSearchResult(
      List.unmodifiable(tracks),
      hasNext: page * 20 < total,
    );
  }

  Future<MusicTrack> resolve(MusicTrack track, CancellationToken token) async {
    if (!RegExp(r'^\d+$').hasMatch(track.id)) {
      throw const FormatException('歌曲标识无效');
    }
    final query = track.query.isEmpty
        ? '${track.title} ${track.artist}'
        : track.query;
    final data = await _searchRows(query, track.page, token);
    final row = (data['list'] as List)
        .whereType<Map>()
        .where((item) => '${item['id']}' == track.id)
        .firstOrNull;
    if (row == null ||
        !RegExp(r'^\d+$').hasMatch('${row['time'] ?? ''}') ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch('${row['sign'] ?? ''}')) {
      throw const FormatException('歌曲签名已失效，请重新搜索');
    }
    final info = row['minfo'];
    final formats = info is List ? info.whereType<Map>() : const <Map>[];
    final mp3 = formats.where((item) => item['format'] == 'mp3').lastOrNull;
    if (mp3 == null || !RegExp(r'^\d+$').hasMatch('${mp3['bitrate']}')) {
      throw const FormatException('此歌曲没有可试听音频');
    }
    final raw = (await network.postForm(
      endpoint.resolve('/ajax.php?act=getUrl'),
      {
        'platform': 'kuwo',
        'songid': track.id,
        'format': 'mp3',
        'bitrate': '${mp3['bitrate']}',
        'time': '${row['time']}',
        'sign': '${row['sign']}',
      },
      headers: _headers,
      cancellation: token,
    )).json;
    final address = raw is Map && raw['code'] == 0 && raw['data'] is Map
        ? (raw['data'] as Map)['url']
        : null;
    if (address is! String) throw const FormatException('此歌曲暂不可试听');
    final uri = Uri.parse(address);
    NetworkTargetPolicy.validateUri(uri);
    const NetworkTargetPolicy().validateAccess(uri, originalOrigin: false);
    return track.withUrl(uri);
  }
}
