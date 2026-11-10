import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/text/display_text.dart';
import '../domain/music_lyrics.dart';
import '../domain/music_track.dart';
import 'public_music_sources.dart';

final class NeteaseMusicDetails {
  NeteaseMusicDetails(this.network, {Uri? endpoint})
    : endpoint = endpoint ?? Uri.https('music.163.com');

  final DocumentClient network;
  final Uri endpoint;
  static final _id = RegExp(r'^[1-9][0-9]{0,19}$');
  static bool supportsLyrics(String provider) =>
      const {'netease', 'lxHelloWorld', 'lxHyw'}.contains(provider);

  Future<MusicLyrics> lyrics(String id, CancellationToken token) async {
    if (!_id.hasMatch(id)) throw const FormatException('歌曲标识无效');
    final raw = (await network.get(
      endpoint
          .resolve('/api/song/lyric')
          .replace(queryParameters: {'id': id, 'lv': '-1', 'tv': '-1'}),
      cancellation: token,
      maxBytes: 256 * 1024,
      networkTimeout: const Duration(seconds: 8),
    )).json;
    if (raw is! Map || raw['code'] != 200) {
      throw const FormatException('网易云歌词暂不可用');
    }
    String lrc(String key) {
      final entry = raw[key];
      final text = entry is Map ? entry['lyric'] : null;
      return text is String ? text : '';
    }

    return MusicLyrics.parse(lrc('lrc'), lrc('tlyric'));
  }

  Future<({String name, List<MusicTrack> tracks, int total})> playlist(
    String input,
    CancellationToken token,
  ) async {
    final id = _playlistId(input);
    final raw = (await network.get(
      endpoint
          .resolve('/api/v6/playlist/detail')
          .replace(queryParameters: {'id': id, 'n': '500'}),
      cancellation: token,
      maxBytes: 4 * 1024 * 1024,
      networkTimeout: const Duration(seconds: 12),
    )).json;
    final list = raw is Map ? raw['playlist'] : null;
    if (raw is! Map ||
        raw['code'] != 200 ||
        list is! Map ||
        list['privacy'] != 0) {
      throw const FormatException('此网易云歌单无法公开访问');
    }
    final title = list['name'];
    final rows = list['tracks'];
    final total = list['trackCount'];
    final name = title is String ? displayText(title) : '';
    if (name.isEmpty || name.length > 80 || rows is! List) {
      throw const FormatException('网易云歌单数据无效');
    }
    final ordered = await _completePlaylist(list, rows, token);
    final tracks = parsePublicMusicRows('netease', '', 1, ordered).tracks;
    return (
      name: name,
      tracks: tracks,
      total: total is int && total >= rows.length ? total : rows.length,
    );
  }

  Future<List<Map>> _completePlaylist(
    Map list,
    List preview,
    CancellationToken token,
  ) async {
    final ids = list['trackIds'];
    final rows = <String, Map>{
      for (final row in preview.take(500).whereType<Map>()) '${row['id']}': row,
    };
    if (ids is! List || ids.isEmpty) return rows.values.toList();
    final order = [
      for (final entry in ids.take(500).whereType<Map>())
        if (_id.hasMatch('${entry['id']}')) '${entry['id']}',
    ];
    if (order.isEmpty) return rows.values.toList();
    final missing = order.where((id) => !rows.containsKey(id)).toSet().toList();
    for (var start = 0; start < missing.length; start += 100) {
      final batch = missing.skip(start).take(100).toSet();
      final data = (await network.get(
        endpoint
            .resolve('/api/song/detail')
            .replace(queryParameters: {'ids': '[${batch.join(',')}]'}),
        cancellation: token,
        maxBytes: 2 * 1024 * 1024,
        networkTimeout: const Duration(seconds: 10),
      )).json;
      if (data is! Map || data['code'] != 200 || data['songs'] is! List) {
        throw const FormatException('网易云歌单曲目暂时无法补齐');
      }
      for (final row in (data['songs'] as List).whereType<Map>()) {
        final id = '${row['id']}';
        if (batch.contains(id)) rows[id] = row;
      }
    }
    return [for (final id in order) ?rows[id]];
  }

  String _playlistId(String input) {
    final value = input.trim();
    if (_id.hasMatch(value)) return value;
    final uri = value.length <= 500 ? Uri.tryParse(value) : null;
    if (uri != null &&
        const {'http', 'https'}.contains(uri.scheme) &&
        const {'music.163.com', 'y.music.163.com'}.contains(uri.host) &&
        uri.userInfo.isEmpty &&
        !uri.hasPort) {
      final page = uri.hasFragment ? Uri.tryParse(uri.fragment) : uri;
      if (page != null &&
          const {'/playlist', '/m/playlist'}.contains(page.path)) {
        final id = page.queryParameters['id'];
        if (id != null && _id.hasMatch(id)) return id;
      }
    }
    throw const FormatException('请输入网易云公开歌单链接或数字 ID');
  }
}
