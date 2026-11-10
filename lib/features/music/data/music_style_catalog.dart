import 'dart:convert';
import 'package:html/parser.dart' as html;

import '../../../core/network/cancellation_token.dart';
import '../../../core/text/display_text.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../domain/music_track.dart';
import 'music_repository.dart';

const musicStyles = {
  '爵士': (21, 32),
  '流行': (6, 9),
  '摇滚': (11, 27),
  '民谣': (28, 83),
  '古典': (27, 28),
  '轻音乐': (15, 34),
  '电子': (24, 33),
  '影视': (133, 79),
  '运动': (99, 69),
  '睡前': (78, 583),
};

typedef MusicStylePlaylist = ({String provider, String id, String name});

final class MusicStyleCatalog {
  MusicStyleCatalog(this.repository);
  final MusicRepository repository;
  static final _id = RegExp(r'^[1-9][0-9]{0,19}$');
  static const _kgHost = 'pc.service.kugou.com';
  static const _qqHeaders = {'Referer': 'https://y.qq.com/'};

  bool allowed(MusicStylePlaylist list) =>
      (repository.policy?.sourceAllowed(repository.sourceFor(list.provider)) ??
          true) &&
      (repository.policy?.textAllowed(list.name) ?? true);

  Future<List<MusicStylePlaylist>> search(
    String provider,
    String style,
    CancellationToken token,
  ) async {
    if (!musicPlaylistProviders.containsKey(provider)) {
      throw const FormatException('未知歌单平台');
    }
    style = repository.validateSearchQuery(style);
    _requireSource(provider);
    final category = musicStyles[style];
    final network = repository.client.network;
    final List<(Object?, Object?)> rows;
    switch (provider) {
      case 'qqPlaylist':
        if (category == null) return [];
        final uri = Uri.https(
          'c.y.qq.com',
          '/splcloud/fcgi-bin/fcg_get_diss_by_tag.fcg',
          {
            'picmid': '1',
            'categoryId': '${category.$1}',
            'sortId': '5',
            'sin': '0',
            'ein': '15',
            'format': 'json',
            'outCharset': 'utf-8',
          },
        );
        final data = (await network.get(
          uri,
          headers: _qqHeaders,
          cancellation: token,
        )).json;
        if (_field(data, 'code') != 0) {
          throw const FormatException('QQ 音乐歌单暂不可用');
        }
        final result = _field(data, 'data');
        rows = _rows(
          _field(result, 'list'),
        ).map((row) => (row['dissid'], row['dissname'])).toList();
      case 'kugouPlaylist':
        if (category == null) return [];
        final uri = Uri.https(_kgHost, '/yueku/v8/special/index/getData.js', {
          'c': '${category.$2}',
          'cdn': 'cdn',
          't': '5',
        });
        final document = await network.get(uri, cancellation: token);
        rows = [
          for (final link
              in html
                  .parse(document.text)
                  .querySelectorAll('strong.collect_specail > a'))
            (
              RegExp(
                r'/special/single/(\d+)-',
              ).firstMatch(link.attributes['href'] ?? '')?[1],
              link.text,
            ),
        ];
        if (rows.isEmpty) throw const FormatException('酷狗歌单暂不可用');
      default:
        final uri = Uri.https('music.163.com', '/api/search/get', {
          's': style,
          'type': '1000',
          'limit': '16',
          'offset': '0',
        });
        final data = (await network.get(uri, cancellation: token)).json;
        if (_field(data, 'code') != 200) {
          throw const FormatException('网易云歌单暂不可用');
        }
        final result = _field(data, 'result');
        rows = _rows(
          _field(result, 'playlists'),
        ).map((row) => (row['id'], row['name'])).toList();
    }
    token.check();
    _requireSource(provider);
    final lists = <String, MusicStylePlaylist>{};
    for (final (rawId, rawName) in rows.take(16)) {
      final id = '$rawId';
      final name = _label(rawName);
      final list = (provider: provider, id: id, name: name);
      if (_id.hasMatch(id) && name.isNotEmpty && allowed(list)) {
        lists[id] = list;
      }
    }
    return lists.values.toList();
  }

  Future<List<MusicTrack>> tracks(
    MusicStylePlaylist list,
    CancellationToken token,
  ) async {
    if (!_id.hasMatch(list.id) ||
        !musicPlaylistProviders.containsKey(list.provider)) {
      throw const FormatException('歌单标识无效');
    }
    if (!allowed(list)) throw const ContentBlocked();
    final tracks = switch (list.provider) {
      'qqPlaylist' => await _qqTracks(list, token),
      'kugouPlaylist' => await _kugouTracks(list, token),
      _ => await _neteaseTracks(list, token),
    };
    token.check();
    if (!allowed(list)) throw const ContentBlocked();
    return {
      for (final track in tracks.where(repository.allowed)) track.key: track,
    }.values.toList();
  }

  Future<List<MusicTrack>> _qqTracks(
    MusicStylePlaylist list,
    CancellationToken token,
  ) async {
    final uri = Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
      'data': jsonEncode({
        'comm': {'ct': 24},
        'req': {
          'module': 'music.srfDissInfo.DissInfo',
          'method': 'CgiGetDiss',
          'param': {
            'disstid': int.parse(list.id),
            'song_begin': 0,
            'song_num': 200,
            'enc_host_uin': '',
            'tag': 1,
          },
        },
      }),
    });
    final data = (await repository.client.network.get(
      uri,
      headers: _qqHeaders,
      cancellation: token,
      maxBytes: 4 * 1024 * 1024,
    )).json;
    final detail = _field(_field(data, 'req'), 'data');
    final rows = _field(detail, 'songlist');
    if (rows is! List) throw const FormatException('QQ 音乐歌单暂不可用');
    final title = _label(_field(_field(detail, 'dirinfo'), 'title'));
    if (title.isNotEmpty &&
        !allowed((provider: list.provider, id: list.id, name: title))) {
      throw const ContentBlocked();
    }
    final url = Uri.https('y.qq.com', '/n/ryqq/playlist/${list.id}');
    return _rows(rows)
        .take(200)
        .map(
          (row) => _track(
            list,
            url,
            row['id'],
            row['title'] ?? row['name'],
            _rows(row['singer'])
                .take(20)
                .map((artist) => _label(artist['name']))
                .where((name) => name.isNotEmpty)
                .join(' / '),
            _duration(row['interval']),
          ),
        )
        .nonNulls
        .toList();
  }

  Future<List<MusicTrack>> _kugouTracks(
    MusicStylePlaylist list,
    CancellationToken token,
  ) async {
    final uri = Uri.https(
      _kgHost,
      '/yueku/v8/special/single/${list.id}-5-9999.html',
    );
    final document = await repository.client.network.get(
      uri,
      cancellation: token,
      maxBytes: 4 * 1024 * 1024,
    );
    // Extract the embedded JSON array as data without evaluating page scripts.
    final json = RegExp(
      r'^\s*var data\s*=\s*(\[.*\]);',
      multiLine: true,
    ).firstMatch(document.text)?[1];
    if (json == null) throw const FormatException('酷狗歌单详情暂不可用');
    return _rows(jsonDecode(json))
        .take(500)
        .map(
          (row) => _track(
            list,
            uri,
            row['songid'],
            row['songname'],
            row['singername'],
            _duration(row['duration']),
          ),
        )
        .nonNulls
        .toList();
  }

  Future<List<MusicTrack>> _neteaseTracks(
    MusicStylePlaylist list,
    CancellationToken token,
  ) async {
    final detail = await repository.importPlaylist(list.id, token);
    final url = Uri.https('music.163.com', '/playlist', {'id': list.id});
    return detail.tracks
        .map(
          (track) => _track(
            list,
            url,
            track.id,
            track.title,
            track.artist,
            track.duration,
          ),
        )
        .nonNulls
        .toList();
  }

  MusicTrack? _track(
    MusicStylePlaylist list,
    Uri uri,
    Object? id,
    Object? title,
    Object? artist,
    Duration duration,
  ) {
    final name = _label(title);
    final singer = _label(artist);
    if (!_id.hasMatch('$id') || name.isEmpty) return null;
    return MusicTrack(
      id: '$id',
      title: name,
      artist: singer,
      url: uri,
      fetchedAt: DateTime.now(),
      provider: list.provider,
      duration: duration,
      downloadable: false,
    );
  }

  void _requireSource(String provider) =>
      repository.policy?.requireSource(repository.sourceFor(provider));

  static Object? _field(Object? value, String key) =>
      value is Map ? value[key] : null;
  static Iterable<Map> _rows(Object? value) =>
      value is List ? value.whereType<Map>() : const [];
  static String _label(Object? value) =>
      value is String && value.length <= 1000 ? displayText(value) : '';
  static Duration _duration(Object? seconds) =>
      Duration(seconds: (int.tryParse('$seconds') ?? 0).clamp(0, 86400));
}
