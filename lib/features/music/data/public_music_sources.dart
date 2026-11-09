import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/text/display_text.dart';
import '../domain/music_track.dart';
import 'website_music_sources.dart';
import 'lx_native_sources.dart';
import 'flac_music_sources.dart';
import 'kugou_music_source.dart';

const musicSources = {
  'myfreemp3': 'MY FREE MP3',
  'netease': '网易云公开音频',
  'audius': 'Audius',
  'flacHi': '无损音乐下载 · 酷我试听',
  'kugou': '酷狗音乐 · 公开音频',
  'lxHelloWorld': '网易云 · LX/Hello World（实验）',
  'lxHyw': '网易云 · LX/HYW 公益（实验）',
};

final class PublicMusicSources {
  PublicMusicSources(this.network);
  final DocumentClient network;
  late final websites = WebsiteMusicSources(network);
  late final lx = LxNativeSources(network);
  late final flac = FlacMusicSources(network);
  late final kugou = KugouMusicSource(network);
  Future<MusicSearchResult> search(
    String provider,
    String query,
    int page,
    CancellationToken? token,
  ) async {
    if (provider == 'flacHi') return flac.search(query, page, token);
    if (provider == KugouMusicSource.provider) {
      return kugou.search(query, page, token);
    }
    if ({'qqmp3', 'musicBox', 'lxGrass'}.contains(provider)) {
      return websites.search(provider, query, page, token);
    }
    final offset = (page - 1) * 30;
    final uri = switch (provider) {
      'audius' => Uri.https('api.audius.co', '/v1/tracks/search', {
        'query': query,
        'limit': '30',
        'offset': '$offset',
        'app_name': 'ZeroPlayer',
      }),
      'archive' => Uri.https('archive.org', '/advancedsearch.php', {
        'q':
            'mediatype:audio AND collection:opensource_audio AND ($query) AND NOT access-restricted-item:true',
        'fl[]': 'identifier,title,creator',
        'rows': '30',
        'page': '$page',
        'output': 'json',
      }),
      _ => Uri.https('music.163.com', '/api/search/get', {
        's': query,
        'type': '1',
        'limit': '30',
        'offset': '$offset',
      }),
    };
    final data = (await network.get(uri, cancellation: token)).json as Map;
    final rows = switch (provider) {
      'audius' => data['data'] as List,
      'archive' => (data['response'] as Map)['docs'] as List,
      _ => (data['result'] as Map?)?['songs'] as List? ?? [],
    };
    return parsePublicMusicRows(provider, query, page, rows);
  }

  Future<MusicTrack> resolve(MusicTrack track, CancellationToken token) async {
    if (track.provider == 'flacHi') return flac.resolve(track, token);
    if (track.provider == KugouMusicSource.provider) {
      return kugou.resolve(track, token);
    }
    if ({'qqmp3', 'musicBox'}.contains(track.provider)) {
      return websites.resolve(track, token);
    }
    if (track.provider.startsWith('lx')) return lx.resolve(track, token);
    if (!RegExp(
      track.provider == 'audius'
          ? r'^[A-Za-z0-9]+$'
          : track.provider == 'archive'
          ? r'^[A-Za-z0-9][A-Za-z0-9._-]*$'
          : r'^\d+$',
    ).hasMatch(track.id)) {
      throw const FormatException('音乐来源标识无效');
    }
    if (track.provider == 'audius') {
      final data =
          (await network.get(
                Uri.https('api.audius.co', '/v1/tracks/${track.id}', {
                  'app_name': 'ZeroPlayer',
                }),
                cancellation: token,
              )).json
              as Map;
      final row = data['data'] as Map;
      if (row['is_stream_gated'] == true ||
          row['is_available'] == false ||
          row['is_delete'] == true) {
        throw const FormatException('此歌曲暂未开放公开播放');
      }
      return MusicTrack(
        id: track.id,
        title: '${row['title'] ?? track.title}',
        artist: '${(row['user'] as Map?)?['name'] ?? track.artist}',
        url: Uri.https('api.audius.co', '/v1/tracks/${track.id}/stream', {
          'app_name': 'ZeroPlayer',
        }),
        duration: track.duration,
        fetchedAt: DateTime.now(),
        provider: 'audius',
        query: track.query,
        page: track.page,
        downloadable:
            row['is_downloadable'] == true && row['is_download_gated'] != true,
        explicit:
            row['parental_warning'] == true ||
            row['parental_warning_type'] != null,
      );
    }
    if (track.provider == 'archive') {
      final data =
          (await network.get(
                Uri.https('archive.org', '/metadata/${track.id}'),
                cancellation: token,
              )).json
              as Map;
      if (data['is_dark'] == true ||
          (data['metadata'] as Map?)?['access-restricted-item'] == 'true') {
        throw const FormatException('该音频不提供公开播放');
      }
      final file = (data['files'] as List)
          .cast<Map>()
          .where(
            (f) =>
                f['private'] != 'true' &&
                RegExp(
                  r'\.(mp3|ogg|flac)$',
                  caseSensitive: false,
                ).hasMatch('${f['name']}'),
          )
          .firstOrNull;
      if (file == null) throw const FormatException('该条目没有公开音频文件');
      return track.withUrl(
        Uri(
          scheme: 'https',
          host: 'archive.org',
          pathSegments: ['download', track.id, ...'${file['name']}'.split('/')],
        ),
      );
    }
    return track.withUrl(
      Uri.https('music.163.com', '/song/media/outer/url', {
        'id': '${track.id}.mp3',
      }),
    );
  }
}

MusicSearchResult parsePublicMusicRows(
  String provider,
  String query,
  int page,
  List rows,
) {
  final tracks = <MusicTrack>[];
  final netease = provider == 'netease' || provider.startsWith('lx');
  for (final row in rows.whereType<Map>()) {
    if (provider == 'audius' &&
        (row['is_stream_gated'] == true ||
            row['is_available'] == false ||
            row['is_delete'] == true ||
            row['is_unlisted'] == true)) {
      continue;
    }
    final id = '${row[provider == 'archive' ? 'identifier' : 'id']}';
    final title = _musicLabel(row[netease ? 'name' : 'title']);
    if (id == 'null' || id.isEmpty || id.length > 512 || title.isEmpty) {
      continue;
    }
    if (netease && !RegExp(r'^\d+$').hasMatch(id)) continue;
    final user = row['user'];
    final artists = row['artists'] ?? row['ar'];
    final artist = switch (provider) {
      'audius' => _musicLabel(user is Map ? user['name'] : null),
      'archive' => _musicLabel(row['creator']),
      _ =>
        artists is List
            ? _musicLabel(
                artists
                    .take(20)
                    .whereType<Map>()
                    .map((a) => _musicLabel(a['name']))
                    .where((a) => a.isNotEmpty)
                    .join(' / '),
              )
            : '',
    };
    final url = switch (provider) {
      'audius' => Uri.https('api.audius.co', '/v1/tracks/$id/stream', {
        'app_name': 'ZeroPlayer',
      }),
      'archive' => Uri.https('archive.org', '/metadata/$id'),
      _ => Uri.https('music.163.com', '/song/media/outer/url', {
        'id': '$id.mp3',
      }),
    };
    final duration = row['duration'] ?? row['dt'];
    final millis = duration is num && duration.isFinite
        ? (duration.toInt() * (provider == 'audius' ? 1000 : 1)).clamp(
            0,
            86400000,
          )
        : 0;
    final artwork = netease ? row['album'] ?? row['al'] : row['artwork'];
    final cover = artwork is Map
        ? artwork[netease ? 'picUrl' : '480x480']
        : null;
    tracks.add(
      MusicTrack(
        id: id,
        title: title,
        artist: artist,
        url: url,
        duration: Duration(milliseconds: millis),
        query: query,
        page: page,
        fetchedAt: DateTime.now(),
        provider: provider,
        downloadable: provider == 'audius'
            ? row['is_downloadable'] == true && row['is_download_gated'] != true
            : !provider.startsWith('lx'),
        cover: cover is String && cover.length <= 2048 ? cover : '',
        explicit:
            row['parental_warning'] == true ||
            row['parental_warning_type'] != null,
      ),
    );
  }
  return MusicSearchResult(
    List.unmodifiable(tracks),
    hasNext: rows.length == 30,
  );
}

String _musicLabel(Object? value) =>
    value is String && value.length <= 1000 ? displayText(value) : '';
