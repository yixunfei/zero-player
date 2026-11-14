import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../../../core/network/cancellation_token.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../domain/music_track.dart';
import 'music_catalog_api.dart';
import 'music_discovery_sources.dart';
import 'music_repository.dart';
import 'netease_music_details.dart';
import 'public_music_sources.dart';

final class MusicStylePlaylist {
  const MusicStylePlaylist(
    this.provider,
    this.id,
    this.name, {
    this.cover = '',
    this.creator = '',
    this.count,
  });
  final String provider, id, name, cover, creator;
  final int? count;

  Uri get uri => switch (provider) {
    'qqPlaylist' => Uri.https('y.qq.com', '/n/ryqq_v2/playlist/$id'),
    'kugouPlaylist' => Uri.https(
      'pc.service.kugou.com',
      '/yueku/v8/special/single/$id-5-9999.html',
    ),
    _ => Uri.https('music.163.com', '/playlist', {'id': id}),
  };
}

typedef MusicPlaylistTracks =
    Future<MusicCatalogPage<MusicTrack>> Function(
      int offset,
      CancellationToken token,
    );

const neteaseRecommendedPlaylists = (
  id: 'recommended',
  name: '推荐歌单',
  group: '全部',
);
const neteaseHighQualityPlaylists = (
  id: 'highquality',
  name: '精品歌单',
  group: '全部',
);
const musicAllCategories = <String, MusicCatalogOption>{
  'neteasePlaylist': (id: '全部', name: '全部歌单', group: '全部'),
  'qqPlaylist': (id: '0', name: '推荐歌单', group: '全部'),
  'kugouPlaylist': (id: '0', name: '全部歌单', group: '全部'),
};

final class MusicStyleCatalog {
  MusicStyleCatalog(this.repository, {MusicCatalogApi? api})
    : api = api ?? MusicCatalogApi(repository.client.network);
  final MusicRepository repository;
  final MusicCatalogApi api;
  late final _netease = NeteaseMusicDetails(api.network, endpoint: api.netease);
  static const _kugouListing = '/yueku/v8/special/index/getData.js';
  static const _trackSize = 50;
  static const _qqSquare = 'music.playlist.PlaylistSquare';

  bool providerAllowed(String provider) =>
      repository.policy?.sourceAllowed(repository.sourceFor(provider)) ?? true;
  bool optionAllowed(MusicCatalogOption option) =>
      repository.policy?.textAllowed(option.name, category: option.group) ??
      true;
  bool allowed(MusicStylePlaylist list) =>
      providerAllowed(list.provider) &&
      (repository.policy?.textAllowed('${list.name} ${list.creator}') ?? true);

  Future<List<MusicCatalogOption>> categories(
    String provider,
    CancellationToken token,
  ) async {
    final all = musicAllCategories[provider];
    if (all == null) throw const FormatException('未知歌单平台');
    _requireSource(provider);
    final options = switch (provider) {
      'qqPlaylist' => await _qqCategories(token),
      'kugouPlaylist' => await _kugouCategories(token),
      _ => await _neteaseCategories(token),
    };
    token.check();
    _requireSource(provider);
    if (options.isEmpty) throw const FormatException('平台未返回歌单分类');
    return {
      for (final option in [all, ...options]) option.id: option,
      all.id: all,
    }.values.toList();
  }

  Future<List<MusicCatalogOption>> _neteaseCategories(
    CancellationToken token,
  ) async {
    final raw = musicCatalogObject(
      (await api.get(
        api.netease.resolve('/api/playlist/catalogue'),
        token,
      )).json,
      200,
    );
    final groups = musicCatalogObject(raw['categories']);
    return [
      for (final row in musicCatalogRows(raw['sub']).whereType<Map>())
        if (musicCatalogLabel(row['name']) case final name when name.isNotEmpty)
          if (musicCatalogLabel(groups['${row['category']}']) case final group
              when group.isNotEmpty)
            (id: name, name: name, group: group),
    ];
  }

  Future<List<MusicCatalogOption>> _qqCategories(
    CancellationToken token,
  ) async {
    final data = await api.qqRequest(_qqSquare, 'GetAllTag', {}, token);
    return [
      for (final group in musicCatalogRows(data['v_group']).whereType<Map>())
        if (musicCatalogLabel(group['group_name']) case final name
            when name.isNotEmpty)
          for (final row in musicCatalogRows(group['v_item']).whereType<Map>())
            if (musicCatalogId.hasMatch('${row['id']}'))
              if (musicCatalogLabel(row['name']) case final label
                  when label.isNotEmpty)
                (
                  id: row['source'] == 1
                      ? 'account:${row['id']}'
                      : '${row['id']}',
                  name: label,
                  group: name,
                ),
    ];
  }

  Future<List<MusicCatalogOption>> _kugouCategories(
    CancellationToken token,
  ) async {
    final doc = await api.get(_kugouPage('0', 1), token);
    return [
      for (final group
          in html
              .parse(doc.text)
              .querySelectorAll('.album_class_box .album_class_list'))
        if (musicCatalogLabel(group.querySelector('h3')?.text) case final name
            when name.isNotEmpty)
          for (final link in group.querySelectorAll('a[href]'))
            if (Uri.tryParse(link.attributes['href']!) case final url?
                when url.path == _kugouListing)
              if (url.queryParameters['c'] case final id?
                  when musicCatalogId.hasMatch(id))
                if (musicCatalogLabel(link.text) case final label
                    when label.isNotEmpty)
                  (id: id, name: label, group: name),
    ];
  }

  Future<MusicCatalogPage<MusicStylePlaylist>> playlists(
    String provider,
    MusicCatalogOption category,
    CancellationToken token, {
    String? query,
    int cursor = 0,
  }) async {
    if (cursor < 0 || !musicAllCategories.containsKey(provider)) {
      throw const FormatException('歌单分类或页码无效');
    }
    _requireSource(provider);
    if (query == null && !optionAllowed(category)) throw const ContentBlocked();
    final result = switch (provider) {
      'qqPlaylist' => await _qqPlaylists(category.id, cursor, token),
      'kugouPlaylist' => await _kugouPlaylists(category.id, cursor, token),
      _ => await _neteasePlaylists(category.id, query, cursor, token),
    };
    token.check();
    _requireSource(provider);
    if (query == null) {
      if (!optionAllowed(category)) throw const ContentBlocked();
    } else {
      repository.validateSearchQuery(query);
    }
    return (
      items: result.items.where(allowed).toList(),
      next: result.next,
      total: result.total,
    );
  }

  Future<MusicCatalogPage<MusicStylePlaylist>> _neteasePlaylists(
    String category,
    String? query,
    int offset,
    CancellationToken token,
  ) async {
    const provider = 'neteasePlaylist';
    const size = 35;
    final highQuality =
        query == null && category == neteaseHighQualityPlaylists.id;
    final recommended =
        query == null && category == neteaseRecommendedPlaylists.id;
    final path = query != null
        ? '/api/search/get'
        : recommended
        ? '/api/personalized/playlist'
        : highQuality
        ? '/api/playlist/highquality/list'
        : '/api/playlist/list';
    final normalized = query == null
        ? null
        : repository.validateSearchQuery(query);
    final uri = api.netease
        .resolve(path)
        .replace(
          queryParameters: {
            'limit': recommended ? '60' : '$size',
            if (normalized != null) ...{
              's': normalized,
              'type': '1000',
            } else if (!recommended) ...{
              'cat': highQuality ? '全部' : category,
              if (!highQuality) 'order': 'hot',
            },
            if (!recommended) (highQuality ? 'lasttime' : 'offset'): '$offset',
          },
        );
    final raw = musicCatalogObject((await api.get(uri, token)).json, 200);
    final data = normalized == null
        ? raw
        : musicCatalogObject(raw['result'] ?? {});
    if (normalized != null && data.isEmpty) {
      return (items: <MusicStylePlaylist>[], total: 0, next: null);
    }
    final rows = musicCatalogRows(
      recommended
          ? raw['result']
          : data['playlists'] ??
                (normalized != null &&
                        musicCatalogCount(data['playlistCount']) == 0
                    ? []
                    : null),
    );
    final total = recommended
        ? rows.length
        : musicCatalogCount(
            data[normalized == null ? 'total' : 'playlistCount'],
          );
    final items = [
      for (final row in rows.whereType<Map>())
        if (row['privacy'] != 10)
          ?_playlist(
            provider,
            row['id'],
            row['name'],
            row['coverImgUrl'] ?? row['picUrl'],
            row['creator'] is Map ? (row['creator'] as Map)['nickname'] : null,
            row['trackCount'],
          ),
    ];
    final more = data[normalized == null ? 'more' : 'hasMore'];
    final timestamp = highQuality ? musicCatalogCount(data['lasttime']) : null;
    return (
      items: items,
      total: total,
      next: recommended || more == false || rows.isEmpty
          ? null
          : highQuality
          ? (timestamp != null &&
                    timestamp > 0 &&
                    (offset == 0 || timestamp < offset)
                ? timestamp
                : null)
          : more == true
          ? offset + rows.length
          : musicCatalogNext(offset, rows.length, size, total),
    );
  }

  Future<MusicCatalogPage<MusicStylePlaylist>> _qqPlaylists(
    String category,
    int cursor,
    CancellationToken token,
  ) async {
    if (category.startsWith('account:')) {
      throw const FormatException('此分类需在 QQ 音乐登录后浏览');
    }
    final id = int.tryParse(category);
    if (id == null || (id != 0 && !musicCatalogId.hasMatch(category))) {
      throw const FormatException('歌单分类无效');
    }
    const size = 20;
    final recommended = id == 0;
    final response = recommended
        ? await api.qqRequest(_qqSquare, 'GetRecommendWhole', {
            'IsReqFeed': true,
            'FeedReq': {'From': cursor * size, 'Size': size},
          }, token)
        : await api.qqRequest(
            'music.playlist.PlayListCategory',
            'get_category_content',
            {
              'caller': '0',
              'category_id': id,
              'size': size,
              'page': cursor,
              'use_page': 1,
            },
            token,
          );
    if (!recommended && response['retcode'] != 0) {
      throw const FormatException('QQ 音乐歌单分类暂不可用');
    }
    final data = musicCatalogObject(
      response[recommended ? 'FeedRsp' : 'content'],
    );
    final rows = musicCatalogRows(data[recommended ? 'List' : 'v_item']);
    final total = musicCatalogCount(data['total_cnt']);
    final more = recommended
        ? data['HasMore'] == true
        : total == null
        ? rows.length >= size
        : (cursor + 1) * size < total;
    return (
      items: [
        for (final row in rows.whereType<Map>())
          ?_qqPlaylist(recommended ? row['Playlist'] : row),
      ],
      total: total,
      next: rows.isNotEmpty && more ? cursor + 1 : null,
    );
  }

  MusicStylePlaylist? _qqPlaylist(Object? value) {
    if (value is! Map || value['basic'] is! Map) return null;
    final row = value['basic'] as Map;
    final cover = row['cover'];
    final creator = row['creator'];
    return _playlist(
      'qqPlaylist',
      row['tid'],
      row['title'],
      cover is Map ? cover['default_url'] : null,
      creator is Map ? creator['nick'] : null,
      row['song_cnt'],
    );
  }

  Uri _kugouPage(String category, int page) => api.kugou
      .resolve(_kugouListing)
      .replace(
        queryParameters: {
          'c': category,
          'cdn': 'cdn',
          't': '5',
          'p': '$page',
          'pagesize': '20',
        },
      );

  Future<MusicCatalogPage<MusicStylePlaylist>> _kugouPlaylists(
    String category,
    int cursor,
    CancellationToken token,
  ) async {
    if (category != '0' && !musicCatalogId.hasMatch(category)) {
      throw const FormatException('歌单分类无效');
    }
    final page = cursor + 1;
    final doc = await api.get(_kugouPage(category, page), token);
    final tree = html.parse(doc.text);
    if (tree.querySelector('.album_class_box') == null) {
      throw const FormatException('酷狗歌单目录暂不可用');
    }
    // The site exposes pagination as a data literal in its HTML.
    final matches = RegExp(
      r'new Page\(\s*(\d+),\s*(\d+),\s*\d+,\s*(\d+)\s*\)',
    ).firstMatch(tree.querySelector('#nvg script')?.text ?? '');
    final total = musicCatalogCount(matches?[2]);
    final size = musicCatalogCount(matches?[3]) ?? 20;
    if (matches != null && musicCatalogCount(matches[1]) != page) {
      throw const FormatException('酷狗返回了不同的歌单页');
    }
    final rows = tree.querySelectorAll('strong.collect_specail > a');
    return (
      items: [
        for (final link in rows)
          ?_playlist(
            'kugouPlaylist',
            RegExp(
              r'^/yueku/v8/special/single/(\d+)-5-\d+\.html$',
            ).firstMatch(link.attributes['href'] ?? '')?[1],
            link.text,
            link.parent?.parent?.querySelector('.pic img')?.attributes['_src'],
            link.parent?.parent?.querySelector('a.singer')?.text,
            null,
          ),
      ],
      total: total,
      next:
          rows.isNotEmpty &&
              (total == null ? rows.length >= size : page * size < total)
          ? page
          : null,
    );
  }

  MusicStylePlaylist? _playlist(
    String provider,
    Object? rawId,
    Object? title,
    Object? cover,
    Object? creator,
    Object? count,
  ) {
    final id = '$rawId';
    final name = musicCatalogLabel(title);
    if (!musicCatalogId.hasMatch(id) || name.isEmpty) return null;
    return MusicStylePlaylist(
      provider,
      id,
      name,
      cover: musicThumbnail(cover is String ? cover : ''),
      creator: musicCatalogLabel(creator),
      count: musicCatalogCount(count),
    );
  }

  Future<MusicPlaylistTracks> open(
    MusicStylePlaylist list,
    CancellationToken token,
  ) async {
    if (!musicCatalogId.hasMatch(list.id) ||
        int.tryParse(list.id) == null ||
        !musicAllCategories.containsKey(list.provider)) {
      throw const FormatException('歌单标识无效');
    }
    if (!allowed(list)) throw const ContentBlocked();
    final fetch = switch (list.provider) {
      'qqPlaylist' => (int offset, CancellationToken token) => _qqTracks(
        list,
        offset,
        token,
      ),
      'kugouPlaylist' => await _openKugou(list, token),
      _ => await _openNetease(list, token),
    };
    token.check();
    return (offset, token) async {
      if (!allowed(list)) throw const ContentBlocked();
      final page = await fetch(offset, token);
      token.check();
      if (!allowed(list)) throw const ContentBlocked();
      return (
        items: page.items.where(repository.allowed).toList(),
        next: page.next,
        total: page.total,
      );
    };
  }

  Future<MusicCatalogPage<MusicTrack>> _qqTracks(
    MusicStylePlaylist list,
    int offset,
    CancellationToken token,
  ) async {
    final data = await api
        .qqRequest('music.srfDissInfo.DissInfo', 'CgiGetDiss', {
          'disstid': int.parse(list.id),
          'song_begin': offset,
          'song_num': _trackSize,
          'enc_host_uin': '',
          'tag': 1,
        }, token);
    final info = musicCatalogObject(data['dirinfo']);
    _requireName(info['title']);
    final rows = musicCatalogRows(data['songlist']);
    final total = musicCatalogCount(data['total_song_num'] ?? info['songnum']);
    return (
      items: [
        for (final row in rows.whereType<Map>())
          ?_track(
            list,
            row['id'],
            row['title'] ?? row['name'],
            row['singer'] is List
                ? (row['singer'] as List)
                      .whereType<Map>()
                      .take(20)
                      .map((s) => musicCatalogLabel(s['name']))
                      .where((name) => name.isNotEmpty)
                      .join(' / ')
                : '',
            _duration(row['interval']),
          ),
      ],
      total: total,
      next: data['hasmore'] == 0 || data['hasmore'] == false
          ? null
          : musicCatalogNext(offset, rows.length, _trackSize, total),
    );
  }

  Future<MusicPlaylistTracks> _openKugou(
    MusicStylePlaylist list,
    CancellationToken token,
  ) async {
    final doc = await api.get(api.kugou.resolve(list.uri.path), token);
    final tree = html.parse(doc.text);
    _requireName(tree.querySelector('.alm_table strong[title]')?.text);
    // Read the embedded JSON array without running the site's scripts.
    final raw = RegExp(
      r'^[ \t]*var data\s*=\s*(\[[^\r\n]*\]);',
      multiLine: true,
    ).firstMatch(doc.text)?[1];
    if (raw == null) throw const FormatException('酷狗歌单详情暂不可用');
    final rows = musicCatalogRows(jsonDecode(raw));
    return (offset, token) async {
      final batch = rows.skip(offset).take(_trackSize).toList();
      return (
        items: [
          for (final row in batch.whereType<Map>())
            ?_track(
              list,
              row['songid'],
              row['songname'],
              row['singername'],
              _duration(row['duration']),
            ),
        ],
        next: musicCatalogNext(offset, batch.length, _trackSize, rows.length),
        total: rows.length,
      );
    };
  }

  Future<MusicPlaylistTracks> _openNetease(
    MusicStylePlaylist list,
    CancellationToken token,
  ) async {
    final detail = await _netease.openPlaylist(list.id, token);
    return (offset, token) async {
      _requireName(detail.name);
      final page = await detail.rows(offset, _trackSize, token);
      return (
        items: [
          for (final track in parsePublicMusicRows(
            'netease',
            '',
            1,
            page.items,
          ).tracks)
            ?_track(
              list,
              track.id,
              track.title,
              track.artist,
              track.duration,
              explicit: track.explicit,
            ),
        ],
        next: page.next,
        total: page.total,
      );
    };
  }

  MusicTrack? _track(
    MusicStylePlaylist list,
    Object? id,
    Object? title,
    Object? artist,
    Duration duration, {
    bool explicit = false,
  }) {
    final name = musicCatalogLabel(title);
    if (!musicCatalogId.hasMatch('$id') || name.isEmpty) return null;
    return MusicTrack(
      id: '$id',
      title: name,
      artist: musicCatalogLabel(artist),
      url: list.uri,
      fetchedAt: DateTime.now(),
      provider: list.provider,
      duration: duration,
      downloadable: false,
      explicit: explicit,
    );
  }

  void _requireSource(String provider) =>
      repository.policy?.requireSource(repository.sourceFor(provider));
  void _requireName(Object? name) {
    if (!(repository.policy?.textAllowed(musicCatalogLabel(name)) ?? true)) {
      throw const ContentBlocked();
    }
  }

  static Duration _duration(Object? seconds) =>
      Duration(seconds: (musicCatalogCount(seconds) ?? 0).clamp(0, 86400));
}
