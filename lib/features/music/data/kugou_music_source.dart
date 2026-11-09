import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/text/display_text.dart';
import '../domain/music_track.dart';

final class KugouMusicSource {
  KugouMusicSource(this.network, {Uri? searchEndpoint, Uri? audioEndpoint})
    : searchEndpoint =
          searchEndpoint ??
          Uri.https('songsearch.kugou.com', '/song_search_v2'),
      audioEndpoint =
          audioEndpoint ?? Uri.https('m.kugou.com', '/app/i/getSongInfo.php');

  final DocumentClient network;
  final Uri searchEndpoint, audioEndpoint;
  static const provider = 'kugou';
  static const _pageSize = 30;
  static final _hash = RegExp(r'^[0-9a-fA-F]{32}$');

  Future<MusicSearchResult> search(
    String query,
    int page,
    CancellationToken? token,
  ) async {
    final document = await network.get(
      searchEndpoint.replace(
        queryParameters: {
          'keyword': query,
          'platform': 'WebFilter',
          'format': 'json',
          'page': '$page',
          'pagesize': '$_pageSize',
        },
      ),
      cancellation: token,
    );
    final raw = document.json;
    final data = raw is Map ? raw['data'] : null;
    final rows = data is Map ? data['lists'] : null;
    if (raw is! Map || raw['status'] != 1 || data is! Map || rows is! List) {
      throw const FormatException('酷狗音乐搜索暂不可用');
    }
    final tracks = <String, MusicTrack>{};
    for (final row in rows.take(_pageSize).whereType<Map>()) {
      final hash = row['FileHash'];
      final title = _text(row['SongName']);
      if (hash is! String || !_hash.hasMatch(hash) || title.isEmpty) continue;
      final id = hash.toUpperCase();
      final seconds = row['Duration'];
      tracks[id] = MusicTrack(
        id: id,
        title: title,
        artist: _text(row['SingerName']),
        url: _audioRequest(id),
        duration: Duration(
          seconds: seconds is int ? seconds.clamp(0, 86400) : 0,
        ),
        query: query,
        page: page,
        fetchedAt: DateTime.now(),
        provider: provider,
        downloadable: false,
      );
    }
    final total = data['total'];
    return MusicSearchResult(
      List.unmodifiable(tracks.values),
      hasNext: rows.isNotEmpty && total is int && total > page * _pageSize,
    );
  }

  Future<MusicTrack> resolve(MusicTrack track, CancellationToken token) async {
    if (!_hash.hasMatch(track.id)) throw const FormatException('酷狗歌曲标识无效');
    final raw = (await network.get(
      _audioRequest(track.id),
      cancellation: token,
      maxBytes: 128 * 1024,
    )).json;
    final hash = raw is Map ? raw['hash'] : null;
    final value = raw is Map ? raw['url'] : null;
    final url = value is String ? Uri.tryParse(value) : null;
    if (raw is! Map ||
        raw['status'] != 1 ||
        hash is! String ||
        hash.toUpperCase() != track.id.toUpperCase() ||
        url == null ||
        url.scheme != 'https' ||
        !url.host.endsWith('.kugou.com') ||
        url.userInfo.isNotEmpty ||
        url.port != 443 ||
        url.hasFragment) {
      throw const FormatException('这首酷狗歌曲暂未开放匿名播放');
    }
    return track.withUrl(url);
  }

  Uri _audioRequest(String hash) =>
      audioEndpoint.replace(queryParameters: {'cmd': 'playInfo', 'hash': hash});

  String _text(Object? value) =>
      value is String && value.length <= 1000 ? displayText(value) : '';
}
