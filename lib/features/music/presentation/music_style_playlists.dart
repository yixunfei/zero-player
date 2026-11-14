import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/poster_image.dart';
import '../../../core/network/cancellation_token.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../data/music_catalog_api.dart';
import '../data/music_style_catalog.dart';
import '../domain/music_track.dart';
import 'music_actions.dart';
import 'music_catalog_controls.dart';

final class MusicStylePlaylists extends StatefulWidget {
  const MusicStylePlaylists({
    super.key,
    required this.services,
    this.initialProvider = 'neteasePlaylist',
    this.initialSection,
    this.catalog,
  });
  final AppServices services;
  final String initialProvider;
  final String? initialSection;
  final MusicStyleCatalog? catalog;

  @override
  State<MusicStylePlaylists> createState() => _MusicStylePlaylistsState();
}

final class _MusicStylePlaylistsState extends State<MusicStylePlaylists> {
  late final _catalog =
      widget.catalog ?? MusicStyleCatalog(widget.services.music);
  final _query = TextEditingController();
  final _scroll = ScrollController();
  late String _provider;
  late MusicCatalogOption _category;
  final _options = <String, List<MusicCatalogOption>>{};
  String? _keyword;
  CancellationToken? _request, _directoryRequest;
  List<MusicStylePlaylist> _lists = [];
  MusicStylePlaylist? _selected;
  MusicPlaylistTracks? _readTracks;
  List<MusicTrack> _tracks = [];
  String? _error, _directoryError;
  int? _nextList, _nextTrack, _listTotal, _trackTotal;
  double _listOffset = 0;
  bool _failedMore = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.initialProvider;
    _category = musicAllCategories[_provider]!;
    final initial = widget.initialSection;
    if (initial == 'recommended') _category = neteaseRecommendedPlaylists;
    unawaited(_loadDirectory(initialGroup: initial));
    if (initial == null || initial == 'recommended') unawaited(_browse());
  }

  @override
  void dispose() {
    _request?.cancel();
    _directoryRequest?.cancel();
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory({String? initialGroup}) async {
    _directoryRequest?.cancel();
    final token = CancellationToken();
    final provider = _provider;
    final previousRequest = _request;
    setState(() {
      _directoryRequest = token;
      _directoryError = null;
    });
    try {
      final options = await _catalog.categories(provider, token);
      token.check();
      if (!mounted) return;
      setState(() => _options[provider] = options);
    } catch (failure) {
      if (mounted && !token.isCancelled) {
        setState(() => _directoryError = _message(failure, '歌单分类暂不可用'));
      }
    } finally {
      if (mounted && !token.isCancelled) {
        setState(() => _directoryRequest = null);
        if (initialGroup != null &&
            initialGroup != 'recommended' &&
            identical(previousRequest, _request) &&
            _keyword == null &&
            _selected == null) {
          final option = (_options[provider] ?? [])
              .where(
                (item) =>
                    item.group == initialGroup && _catalog.optionAllowed(item),
              )
              .firstOrNull;
          if (option != null || _lists.isEmpty) await _browse(category: option);
        }
      }
    }
  }

  void _selectProvider(String provider) {
    if (_provider == provider) return;
    _provider = provider;
    if (!_options.containsKey(provider)) {
      unawaited(_loadDirectory());
    } else {
      _directoryRequest?.cancel();
      _directoryRequest = null;
      _directoryError = null;
    }
    unawaited(_browse(category: musicAllCategories[provider]));
  }

  Future<void> _browse({MusicCatalogOption? category, String? keyword}) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    return _load(() {
      _category = category ?? _category;
      _keyword = keyword;
      if (keyword == null) _query.clear();
      _lists = [];
      _nextList = _listTotal = null;
    }, (token) => _listPage(0, token));
  }

  Future<void> _listPage(int cursor, CancellationToken token) async {
    final result = await _catalog.playlists(
      _provider,
      _category,
      token,
      query: _keyword,
      cursor: cursor,
    );
    token.check();
    if (!mounted) return;
    setState(() {
      final known = _lists.map((item) => item.id).toSet();
      final added = result.items.where((item) => known.add(item.id)).toList();
      _lists = [..._lists, ...added];
      final next = result.next;
      _nextList =
          next != null &&
              next != cursor &&
              (added.isNotEmpty || result.items.isEmpty)
          ? next
          : null;
      _listTotal = result.total ?? _listTotal;
    });
  }

  Future<void> _open(MusicStylePlaylist list) {
    _listOffset = _scroll.hasClients ? _scroll.offset : 0;
    return _load(() {
      _selected = list;
      _readTracks = null;
      _tracks = [];
      _nextTrack = _trackTotal = null;
    }, (token) => _trackPage(list, 0, token));
  }

  Future<void> _trackPage(
    MusicStylePlaylist list,
    int cursor,
    CancellationToken token,
  ) async {
    final reader = _readTracks ?? await _catalog.open(list, token);
    token.check();
    final result = await reader(cursor, token);
    token.check();
    if (!mounted) return;
    setState(() {
      _readTracks = reader;
      final known = _tracks.map((item) => item.key).toSet();
      final added = result.items.where((item) => known.add(item.key)).toList();
      _tracks = [..._tracks, ...added];
      final next = result.next;
      _nextTrack =
          next != null &&
              next > cursor &&
              (added.isNotEmpty || result.items.isEmpty)
          ? next
          : null;
      _trackTotal = result.total ?? _trackTotal;
    });
  }

  Future<void> _load(
    VoidCallback reset,
    Future<void> Function(CancellationToken) action, {
    bool more = false,
  }) async {
    _request?.cancel();
    final token = CancellationToken();
    setState(() {
      _request = token;
      _error = null;
      _failedMore = more;
      reset();
    });
    try {
      await action(token);
    } catch (failure) {
      if (mounted && !token.isCancelled) {
        setState(() => _error = _message(failure, more ? '下一页暂不可用' : '无法加载歌单'));
      }
    } finally {
      if (mounted && !token.isCancelled) setState(() => _request = null);
    }
  }

  String _message(Object error, String fallback) => switch (error) {
    ContentBlocked() => '歌单或平台已被当前过滤规则屏蔽',
    FormatException() => error.message,
    _ => fallback,
  };

  void _back() {
    _request?.cancel();
    setState(() {
      _request = null;
      _selected = null;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selected == null && _scroll.hasClients) {
        _scroll.jumpTo(_listOffset.clamp(0, _scroll.position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.services.contentPolicy,
    builder: (context, _) {
      final selected = _selected;
      if (selected != null) return _detail(selected);
      final allowed =
          _catalog.providerAllowed(_provider) &&
          (_keyword == null
              ? _catalog.optionAllowed(_category)
              : widget.services.contentPolicy.textAllowed(_keyword!));
      final lists = allowed
          ? _lists.where(_catalog.allowed).toList()
          : <MusicStylePlaylist>[];
      return ListView.builder(
        key: const PageStorageKey('music-style-lists'),
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        itemCount: lists.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _controls(allowed);
          if (i > lists.length) {
            return allowed
                ? _footer(
                    empty: lists.isEmpty ? '没有可显示的歌单' : null,
                    next: _nextList,
                    label: '加载更多歌单',
                    load: _listPage,
                  )
                : const SizedBox.shrink();
          }
          final list = lists[i - 1];
          return ListTile(
            leading: _cover(list),
            title: Text(
              list.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _subtitle(list),
            trailing: MusicCatalogCopyButton(uri: list.uri, label: '复制歌单网页链接'),
            onTap: () => _open(list),
          );
        },
      );
    },
  );

  Widget _controls(bool allowed) {
    final total = _listTotal;
    final options = [
      ...(_options[_provider] ?? [musicAllCategories[_provider]!]),
      if (_provider == 'neteasePlaylist') ...[
        neteaseRecommendedPlaylists,
        neteaseHighQualityPlaylists,
      ],
    ].where(_catalog.optionAllowed).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final entry in musicPlaylistProviders.entries)
              ChoiceChip(
                selected: _provider == entry.key,
                label: Text(entry.value),
                onSelected: _catalog.providerAllowed(entry.key)
                    ? (_) => _selectProvider(entry.key)
                    : null,
              ),
            if (allowed)
              MusicCatalogCopyButton(
                label: '复制歌单平台网页链接',
                uri: switch (_provider) {
                  'qqPlaylist' => Uri.https('y.qq.com', '/n/ryqq_v2/category'),
                  'kugouPlaylist' => Uri.https(
                    'www.kugou.com',
                    '/yy/special/index/1.html',
                  ),
                  _ => Uri.https('music.163.com', '/discover/playlist'),
                },
              ),
          ],
        ),
        if (_catalog.providerAllowed(_provider) &&
            _provider == 'neteasePlaylist')
          TextField(
            controller: _query,
            maxLength: 100,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: InputDecoration(
              labelText: '搜索歌单风格或名称',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: '搜索歌单',
                onPressed: () => _search(_query.text),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        if (_catalog.providerAllowed(_provider))
          MusicCatalogPicker(
            options: options,
            group: options.any((item) => item.group == _category.group)
                ? _category.group
                : options.firstOrNull?.group,
            selected: _keyword == null ? _category.id : null,
            label: '选择歌单分类',
            onSelected: (option) => _browse(category: option),
          ),
        if (_directoryRequest != null) const LinearProgressIndicator(),
        if (_directoryError case final error?)
          ListTile(
            title: Text(error),
            trailing: TextButton(
              onPressed: _loadDirectory,
              child: const Text('重试分类'),
            ),
          ),
        if (!allowed) const Text('当前平台或分类已被过滤'),
        if (allowed && total != null) Text('源站 $total 个歌单'),
      ],
    );
  }

  void _search(String value) {
    final keyword = value.trim();
    unawaited(_browse(keyword: keyword.isEmpty ? null : keyword));
  }

  Widget _detail(MusicStylePlaylist list) {
    final allowed = _catalog.allowed(list);
    final services = widget.services;
    final tracks = allowed
        ? _tracks.where(services.music.allowed).toList()
        : <MusicTrack>[];
    return ListView.builder(
      key: ValueKey('${list.provider}:${list.id}'),
      padding: const EdgeInsets.all(16),
      itemCount: tracks.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _detailHeader(list, tracks, allowed);
        }
        if (index > tracks.length) {
          return allowed
              ? _footer(
                  empty: tracks.isEmpty ? '歌单内没有可显示的曲目' : null,
                  next: _nextTrack,
                  label: '加载更多曲目',
                  load: (cursor, token) => _trackPage(list, cursor, token),
                )
              : const SizedBox.shrink();
        }
        final track = tracks[index - 1];
        return ListTile(
          leading: const Icon(Icons.music_note_outlined),
          title: Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: MusicTrackMenu(services: services, track: track),
          onTap: () => services.musicPlayer.select(tracks, index - 1),
        );
      },
    );
  }

  Widget _detailHeader(
    MusicStylePlaylist list,
    List<MusicTrack> tracks,
    bool allowed,
  ) {
    final total = _trackTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: IconButton(
            tooltip: '返回在线歌单',
            onPressed: _back,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(allowed ? list.name : '歌单已被过滤'),
          trailing: allowed
              ? MusicCatalogCopyButton(uri: list.uri, label: '复制歌单网页链接')
              : null,
        ),
        if (allowed)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                total == null
                    ? '已加载 ${tracks.length} 首'
                    : '已加载 ${tracks.length} 首 · 源站 $total 首',
              ),
              TextButton(
                onPressed: tracks.isEmpty
                    ? null
                    : () => widget.services.musicPlayer.select(tracks, 0),
                child: const Text('匹配播放'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _footer({
    required String? empty,
    required int? next,
    required String label,
    required Future<void> Function(int, CancellationToken) load,
  }) {
    if (_request != null) return const LinearProgressIndicator();
    final error = _error;
    final cursor = error != null && !_failedMore ? 0 : next;
    if (cursor != null) {
      final button = TextButton(
        onPressed: () =>
            _load(() {}, (token) => load(cursor, token), more: cursor != 0),
        child: Text(error == null ? label : '重试'),
      );
      return error == null
          ? button
          : ListTile(title: Text(error), trailing: button);
    }
    return empty == null ? const SizedBox.shrink() : Text(empty);
  }

  Widget _cover(MusicStylePlaylist list) => list.cover.isEmpty
      ? const Icon(Icons.library_music_outlined)
      : SizedBox.square(
          dimension: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: PosterImage(
              url: list.cover,
              width: 120,
              showRetry: false,
              placeholderIcon: Icons.library_music_outlined,
            ),
          ),
        );

  Widget? _subtitle(MusicStylePlaylist list) {
    final text = [
      if (list.creator.isNotEmpty) list.creator,
      if (list.count case final count?) '$count 首',
    ].join(' · ');
    return text.isEmpty
        ? null
        : Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
