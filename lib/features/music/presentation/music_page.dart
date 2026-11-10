import 'dart:async';
import 'dart:math';
import '../data/music_library.dart';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../application/music_browser.dart';
import '../application/music_controller.dart';
import '../domain/music_track.dart';
import '../domain/music_match.dart';
import '../data/public_music_sources.dart';
import 'music_player.dart';
import 'music_actions.dart';
import 'music_library_panel.dart';
import 'music_discovery.dart';
import 'music_source_selector.dart';
import 'music_style_playlists.dart';
import '../../../app/poster_image.dart';

final class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.services});
  final AppServices services;
  @override
  State<MusicPage> createState() => _MusicPageState();
}

final class _MusicPageState extends State<MusicPage> {
  late final MusicBrowser browser = widget.services.musicBrowser;
  late final MusicController player = widget.services.musicPlayer;
  late final _query = TextEditingController(text: browser.query);
  final _scroll = ScrollController();
  late String _view;
  String _searchKind = '综合';

  @override
  void initState() {
    super.initState();
    _view = browser.query.isEmpty ? 'discover' : 'search';
    browser.addListener(_prepareSearchResults);
    widget.services.settings.addListener(_prepareSearchResults);
    _prepareSearchResults();
    unawaited(browser.load());
    unawaited(widget.services.musicLibrary.load());
    unawaited(widget.services.musicDownloads.load());
    if (browser.query.isEmpty &&
        widget.services.musicRecommendations.items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(widget.services.musicRecommendations.initialize());
        }
      });
    }
  }

  void _search(String query, {int page = 1}) {
    setState(() => _view = 'search');
    _query.text = query;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(browser.search(query, page: page));
  }

  @override
  void dispose() {
    browser.removeListener(_prepareSearchResults);
    widget.services.settings.removeListener(_prepareSearchResults);
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _prepareSearchResults() {
    if (browser.result.tracks.isEmpty) return;
    player.prepareResults(
      groupMusicTracks(
        browser.result.tracks.where(widget.services.music.allowed),
        enabled: widget.services.settings.value.musicAggregate,
      ),
    );
  }

  List<List<MusicTrack>> _groups(Iterable<MusicTrack> tracks) =>
      groupMusicTracks(
        tracks.where(
          (track) =>
              _searchKind != '歌手' ||
              track.artist.toLowerCase().contains(browser.query.toLowerCase()),
        ),
        enabled: widget.services.settings.value.musicAggregate,
      );

  Future<void> _playResults(List<List<MusicTrack>> groups, int index) {
    player.prepareResults([groups[index], ...groups.skip(index + 1).take(2)]);
    return player.select(
      groups.map((group) => group.first).toList(),
      index,
      variants: {
        for (final group in groups)
          if (group.length > 1) group.first.key: group.skip(1).toList(),
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      browser,
      player,
      widget.services.musicDownloads,
      widget.services.contentPolicy,
      widget.services.settings,
    ]),
    builder: (context, _) {
      final downloads = widget.services.musicDownloads;
      final local = downloads.searchLocal(browser.query);
      final merged = {for (final track in local) track.key: track};
      for (final track in browser.result.tracks.where(
        widget.services.music.allowed,
      )) {
        merged.putIfAbsent(track.key, () => track);
      }
      final groups = _groups(merged.values);
      return Column(
        children: [
          _tabs(),
          Expanded(
            child: _view == 'discover'
                ? MusicDiscovery(
                    services: widget.services,
                    onSearch: _search,
                    controls: _searchControls(),
                  )
                : _view == 'styles'
                ? MusicStylePlaylists(services: widget.services)
                : _view != 'search'
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: MusicLibraryPanel(
                      services: widget.services,
                      view: _view,
                    ),
                  )
                : ListView.builder(
                    key: const PageStorageKey('music-results'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: groups.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) return _header(context);
                      if (index == groups.length + 1) return _footer();
                      return _track(groups, index - 1);
                    },
                  ),
          ),
          MusicPlayer(controller: player),
        ],
      );
    },
  );

  Widget _tabs() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 8,
        children: [
          for (final item in const [
            ('discover', '发现音乐'),
            ('search', '搜索'),
            ('styles', '风格歌单'),
            ('playlists', '我的歌单'),
            ('history', '播放历史'),
            ('downloads', '离线音乐'),
          ])
            ChoiceChip(
              label: Text(item.$2),
              selected: _view == item.$1,
              onSelected: (_) {
                setState(() => _view = item.$1);
                if (item.$1 == 'discover' &&
                    widget.services.musicRecommendations.items.isEmpty) {
                  unawaited(widget.services.musicRecommendations.initialize());
                }
              },
            ),
        ],
      ),
    ),
  );

  Widget _header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('在线音乐', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      _searchControls(),
      Text('推荐搜索', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final query in [
            '周杰伦',
            '陈奕迅',
            'Taylor Swift',
            'Adele',
            '钢琴',
            '爵士',
          ])
            ActionChip(label: Text(query), onPressed: () => _search(query)),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        '搜索结果可逐首播放，或选择一首后按列表连续播放。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (browser.loading) const LinearProgressIndicator(),
      if (browser.sourceNotice != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(browser.sourceNotice!),
        ),
      if (browser.error != null)
        ListTile(
          title: Text(browser.error!),
          trailing: TextButton(
            onPressed: () => _search(browser.query, page: browser.page),
            child: const Text('重试'),
          ),
        ),
      if (!browser.loading && browser.error == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            browser.query.isEmpty
                ? '输入歌名或歌手，开始搜索音乐。'
                : '“${browser.query}” · 第 ${browser.page} 页',
          ),
        ),
    ],
  );

  Widget _searchControls() => Column(
    children: [
      Wrap(
        spacing: 8,
        children: [
          for (final kind in ['综合', '歌手', '主题'])
            ChoiceChip(
              label: Text(kind),
              selected: _searchKind == kind,
              onSelected: (_) => setState(() => _searchKind = kind),
            ),
          if (_searchKind == '主题')
            for (final theme in ['爵士', '钢琴', '助眠', '运动', '电影原声'])
              ActionChip(label: Text(theme), onPressed: () => _search(theme)),
          if (browser.result.tracks.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.shuffle),
              label: const Text('随机播放结果'),
              onPressed: () => musicAction(context, () async {
                final groups = _groups(
                  browser.result.tracks.where(widget.services.music.allowed),
                );
                if (groups.isEmpty) return;
                await player.setMode(MusicPlayMode.shuffle);
                await _playResults(groups, Random().nextInt(groups.length));
              }),
            ),
        ],
      ),
      MusicSourceSelector(
        services: widget.services,
        value: browser.provider,
        onChanged: browser.selectProvider,
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('music-search'),
        controller: _query,
        maxLength: 100,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: _searchKind == '主题' ? '搜索主题，如：爵士、钢琴、助眠' : '搜索歌名或歌手',
          counterText: '',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: '搜索音乐',
            onPressed: () => _search(_query.text),
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
        onSubmitted: _search,
      ),
      const SizedBox(height: 12),
    ],
  );

  Widget _track(List<List<MusicTrack>> groups, int index) {
    final group = groups[index];
    final track = group.first;
    final selected = player.selected?.key == track.key;
    return Card(
      child: ListTile(
        key: ValueKey('music-${track.id}'),
        selected: selected,
        leading: track.cover.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: PosterImage(
                    url: track.cover,
                    placeholderIcon: Icons.album_outlined,
                  ),
                ),
              )
            : Icon(
                selected && player.playing
                    ? Icons.equalizer
                    : Icons.music_note_outlined,
              ),
        title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${track.artist} · ${widget.services.musicDownloads.completed(track) != null
              ? '已下载 · 本地播放'
              : group.length > 1
              ? '${group.length} 个版本 · 自动选源'
              : musicSources[track.provider] ?? track.provider}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.services.musicDownloads.completed(track) != null)
              const Tooltip(
                message: '已下载 · 优先本地播放',
                child: Icon(Icons.offline_pin_outlined, size: 20),
              ),
            Text(musicTime(track.duration)),
            MusicTrackMenu(
              services: widget.services,
              track: track,
              alternatives: group.skip(1).toList(),
            ),
          ],
        ),
        onTap: () => _playResults(groups, index),
      ),
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        if (!browser.loading &&
            browser.error == null &&
            browser.query.isNotEmpty &&
            browser.result.tracks
                .where(widget.services.music.allowed)
                .isEmpty &&
            widget.services.musicDownloads.searchLocal(browser.query).isEmpty)
          const Text('没有找到可显示的歌曲，试试其他歌名或歌手。'),
        if (!browser.loading &&
            browser.error == null &&
            browser.query.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [
              OutlinedButton.icon(
                onPressed: browser.page > 1
                    ? () => _search(browser.query, page: browser.page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('上一页'),
              ),
              OutlinedButton.icon(
                onPressed: browser.result.hasNext
                    ? () => _search(browser.query, page: browser.page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('下一页'),
              ),
            ],
          ),
      ],
    ),
  );
}
