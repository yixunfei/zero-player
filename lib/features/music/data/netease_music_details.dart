import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../domain/music_lyrics.dart';
import '../domain/music_track.dart';
import 'music_catalog_api.dart';
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
    final list = await openPlaylist(input, token, previewSize: 500);
    if (list.name.length > 80) throw const FormatException('网易云歌单数据无效');
    final tracks = <MusicTrack>[];
    for (var offset = 0; offset < list.available && offset < 500;) {
      final size = (500 - offset).clamp(0, 100);
      final page = await list.rows(offset, size, token);
      tracks.addAll(parsePublicMusicRows('netease', '', 1, page.items).tracks);
      final next = page.next;
      if (next == null) break;
      offset = next;
    }
    return (name: list.name, tracks: tracks, total: list.total);
  }

  Future<NeteasePlaylist> openPlaylist(
    String input,
    CancellationToken token, {
    int previewSize = 50,
  }) async {
    final id = _playlistId(input);
    final raw = (await network.get(
      endpoint
          .resolve('/api/v6/playlist/detail')
          .replace(queryParameters: {'id': id, 'n': '$previewSize'}),
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
    final name = musicCatalogLabel(title);
    if (name.isEmpty || rows is! List) {
      throw const FormatException('网易云歌单数据无效');
    }
    final ids = list['trackIds'];
    final preview = {
      for (final row in rows.whereType<Map>())
        if (_id.hasMatch('${row['id']}')) '${row['id']}': row,
    };
    final order = [
      if (ids is List)
        for (final entry in ids.whereType<Map>())
          if (_id.hasMatch('${entry['id']}')) '${entry['id']}',
    ];
    final ordered = order.isEmpty ? preview.keys.toList() : order;
    return NeteasePlaylist._(
      this,
      preview,
      ordered,
      name: name,
      total: total is int && total >= ordered.length ? total : ordered.length,
    );
  }

  Future<Map<String, Map>> _songs(
    Set<String> ids,
    CancellationToken token,
  ) async {
    if (ids.isEmpty) return {};
    final data = (await network.get(
      endpoint
          .resolve('/api/song/detail')
          .replace(queryParameters: {'ids': '[${ids.join(',')}]'}),
      cancellation: token,
      maxBytes: 2 * 1024 * 1024,
      networkTimeout: const Duration(seconds: 10),
    )).json;
    if (data is! Map || data['code'] != 200 || data['songs'] is! List) {
      throw const FormatException('网易云歌单曲目暂时无法补齐');
    }
    token.check();
    return {
      for (final row in (data['songs'] as List).whereType<Map>())
        if (ids.contains('${row['id']}')) '${row['id']}': row,
    };
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

final class NeteasePlaylist {
  NeteasePlaylist._(
    this._details,
    this._preview,
    this._order, {
    required this.name,
    required this.total,
  });

  final NeteaseMusicDetails _details;
  final Map<String, Map> _preview;
  final List<String> _order;
  final String name;
  final int total;
  int get available => _order.length;
  Map<String, int> ranks(int offset, int size) => {
    for (
      var index = offset;
      index < offset + size && index < _order.length;
      index++
    )
      _order[index]: index + 1,
  };

  Future<MusicCatalogPage<Map>> rows(
    int offset,
    int size,
    CancellationToken token,
  ) async {
    if (offset < 0 || size < 1 || size > 100) {
      throw const FormatException('歌单页码无效');
    }
    final ids = _order.skip(offset).take(size).toList();
    final fetched = await _details._songs(
      ids.where((id) => !_preview.containsKey(id)).toSet(),
      token,
    );
    token.check();
    return (
      items: [for (final id in ids) ?(_preview[id] ?? fetched[id])],
      next: offset + ids.length < available ? offset + ids.length : null,
      total: total,
    );
  }
}
