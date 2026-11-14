import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../data/music_recommendations.dart';
import '../data/music_collections.dart';
import '../data/music_style_catalog.dart';
import 'music_cards.dart';
import 'music_chart_browser.dart';

/// Music metadata discovery stays independent from the selected playback channel.
final class MusicDiscovery extends StatelessWidget {
  const MusicDiscovery({
    super.key,
    required this.services,
    required this.onSearch,
    required this.controls,
    this.onPlaylists,
    this.onOpenPlaylist,
  });
  final AppServices services;
  final ValueChanged<String> onSearch;
  final Widget controls;
  final void Function(String provider, String? section)? onPlaylists;
  final ValueChanged<MusicStylePlaylist>? onOpenPlaylist;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.musicRecommendations,
      services.contentPolicy,
    ]),
    builder: (context, _) {
      final feed = services.musicRecommendations;
      return feed.category == '榜单'
          ? _charts(context, feed)
          : _recommendations(context, feed);
    },
  );

  Widget _charts(BuildContext context, MusicRecommendations feed) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: controls,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: _categoryChips(feed),
      ),
      Expanded(
        child: MusicChartBrowser(services: services, onSearch: onSearch),
      ),
    ],
  );

  Widget _recommendations(BuildContext context, MusicRecommendations feed) {
    final visible = feed.visible;
    final items = feed.items
        .where(
          (i) =>
              visible &&
              services.contentPolicy.textAllowed(
                '${i.title} ${i.artist} ${i.description}',
              ),
        )
        .toList();
    return CustomScrollView(
      key: const PageStorageKey('music-discovery'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: controls,
          ),
        ),
        SliverToBoxAdapter(child: _header(context, feed)),
        if (feed.category == '推荐' && onOpenPlaylist != null)
          SliverToBoxAdapter(child: _recommendPlaylists(context, feed)),
        MusicSongSliver(items: items, onSearch: onSearch),
        if (feed.hasMore && feed.visible)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(
                onPressed: feed.loading ? null : feed.loadMore,
                child: Text(
                  feed.loading
                      ? '正在加载曲目…'
                      : feed.pageError == null
                      ? '加载更多曲目'
                      : '重试下一页曲目',
                ),
              ),
            ),
          ),
        if (visible && !feed.loading && !feed.hasMore && items.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: TextButton(
                onPressed: () => feed.load(feed.chart, refresh: true),
                child: const Text('重新加载推荐音乐'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _header(BuildContext context, MusicRecommendations feed) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('发现音乐', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        const Text('从喜欢的平台发现新歌，选择歌曲后搜索收听。'),
        const SizedBox(height: 16),
        _categoryChips(feed),
        const SizedBox(height: 12),
        _recommendationControls(feed),
        const SizedBox(height: 8),
        const Text('点击封面后，通过当前音乐渠道搜索；推荐内容不指定播放来源。'),
        if (feed.loading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (feed.notice != null || feed.pageError != null || !feed.visible)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              !feed.visible ? '当前栏目已被过滤' : (feed.pageError ?? feed.notice)!,
            ),
          ),
        if (feed.total case final total? when feed.visible)
          Text('已加载 ${feed.items.length} 首 · 源站 $total 首'),
      ],
    ),
  );

  Widget _categoryChips(MusicRecommendations feed) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final category in musicCategories)
        ChoiceChip(
          label: Text(category),
          selected: feed.category == category,
          onSelected: (selected) {
            if (!selected) return;
            if (category == '榜单') {
              feed.selectChartPlatform(feed.chartPlatform);
            } else {
              feed.load(
                category == '推荐'
                    ? feed.homepage
                    : musicCollections.entries
                          .firstWhere(
                            (entry) => entry.value.category == category,
                          )
                          .key,
              );
            }
          },
        ),
      if (onPlaylists != null)
        for (final section in ['情感', '主题'])
          ActionChip(
            label: Text(section),
            onPressed: () => onPlaylists!('neteasePlaylist', section),
          ),
    ],
  );

  Widget _recommendationControls(MusicRecommendations feed) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final chart
          in (feed.category == '推荐'
                  ? musicHomepages
                  : {
                      for (final e in musicCollections.entries)
                        if (e.value.category == feed.category)
                          e.key: e.value.title,
                    })
              .entries)
        ChoiceChip(
          label: Text(chart.value),
          selected: feed.chart == chart.key,
          onSelected: (_) => feed.load(chart.key),
        ),
      IconButton(
        tooltip: '刷新推荐音乐',
        onPressed: feed.loading
            ? null
            : () => feed.load(feed.chart, refresh: true),
        icon: const Icon(Icons.refresh),
      ),
      if (onPlaylists != null)
        ActionChip(
          label: Text(
            feed.chart == 'appleHome'
                ? '浏览在线歌单'
                : feed.category == '推荐'
                ? '推荐歌单'
                : '浏览源站${feed.category}歌单',
          ),
          onPressed: () {
            if (feed.chart == 'qqHome') {
              onPlaylists!('qqPlaylist', null);
            } else {
              onPlaylists!('neteasePlaylist', switch (feed.chart) {
                'home' => 'recommended',
                'appleHome' => null,
                _ => feed.category,
              });
            }
          },
        ),
    ],
  );

  Widget _recommendPlaylists(BuildContext context, MusicRecommendations feed) {
    final lists = feed.recommendPlaylists;
    if (lists.isEmpty && !feed.playlistsLoading) return const SizedBox.shrink();
    final provider = feed.chart == 'qqHome' ? 'qqPlaylist' : 'neteasePlaylist';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('推荐歌单', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (onPlaylists != null)
                TextButton(
                  onPressed: () => onPlaylists!(provider, null),
                  child: const Text('浏览全部'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 216,
            child: lists.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: lists.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 148,
                      child: MusicPlaylistCard(
                        list: lists[index],
                        dense: true,
                        onTap: () => onOpenPlaylist?.call(lists[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}