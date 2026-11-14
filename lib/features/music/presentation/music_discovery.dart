import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/poster_card.dart';
import '../data/music_recommendations.dart';
import '../data/music_collections.dart';
import '../data/music_catalog_api.dart';
import 'music_catalog_controls.dart';

/// Music metadata discovery stays independent from the selected playback channel.
final class MusicDiscovery extends StatelessWidget {
  const MusicDiscovery({
    super.key,
    required this.services,
    required this.onSearch,
    required this.controls,
    this.onPlaylists,
  });
  final AppServices services;
  final ValueChanged<String> onSearch;
  final Widget controls;
  final void Function(String provider, String? section)? onPlaylists;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.musicRecommendations,
      services.contentPolicy,
    ]),
    builder: (context, _) {
      final feed = services.musicRecommendations;
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
          ..._header(context, feed),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final columns =
                    (constraints.crossAxisExtent / (144 * scale.clamp(1, 1.4)))
                        .floor()
                        .clamp(1, 7);
                final width =
                    (constraints.crossAxisExtent - (columns - 1) * 12) /
                    columns;
                return SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = items[index];
                      return PosterCard(
                        key: ValueKey('music-recommendation-$index'),
                        title: item.title,
                        poster: item.cover,
                        subtitle: item.rank == null
                            ? item.artist
                            : '#${item.rank} ${item.artist}'.trimRight(),
                        description: item.description.isEmpty
                            ? '点击封面，通过当前渠道搜索这首音乐。'
                            : item.description,
                        placeholderIcon: Icons.album_outlined,
                        informationLabel: '歌曲信息',
                        onTap: () => onSearch(item.query),
                      );
                    },
                    childCount: items.length,
                    addAutomaticKeepAlives: false,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                    mainAxisExtent: width + 72 * scale,
                  ),
                );
              },
            ),
          ),
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
            if (feed.category != '榜单' ||
                feed.selectedChart != null ||
                feed.chart == 'wfu')
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
    },
  );
  List<Widget> _header(BuildContext context, MusicRecommendations feed) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: controls,
      ),
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发现音乐', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            const Text('从喜欢的平台发现新歌，选择歌曲后搜索收听。'),
            const SizedBox(height: 16),
            Wrap(
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
                                      (entry) =>
                                          entry.value.category == category,
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
            ),
            const SizedBox(height: 12),
            if (feed.category == '榜单')
              _chartControls(feed)
            else
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
      ),
    ),
  ];

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

  Widget _chartControls(MusicRecommendations feed) {
    final selected = feed.selectedChart;
    final uri = feed.chartUri;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final entry in musicCatalogPlatforms.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected:
                    feed.chart != 'wfu' && feed.chartPlatform == entry.key,
                onSelected: (value) {
                  if (value) feed.selectChartPlatform(entry.key);
                },
              ),
            ChoiceChip(
              label: const Text('WFU 音乐精选'),
              selected: feed.chart == 'wfu',
              onSelected: (_) => feed.load('wfu'),
            ),
            if (uri != null)
              MusicCatalogCopyButton(uri: uri, label: '复制榜单网页链接'),
            if (selected != null || feed.chart == 'wfu')
              IconButton(
                tooltip: '刷新榜单曲目',
                onPressed: feed.loading
                    ? null
                    : () => feed.load(feed.chart, refresh: true),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        if (feed.chart != 'wfu') ...[
          MusicCatalogPicker(
            options: feed.charts,
            group: selected?.group ?? feed.charts.firstOrNull?.group,
            selected: selected?.id,
            label: '选择榜单',
            onSelected: feed.selectChart,
          ),
          if (feed.chartDirectoryLoading) const LinearProgressIndicator(),
          if (feed.chartDirectoryError == null &&
              !feed.chartDirectoryLoading &&
              feed.charts.isEmpty &&
              feed.visible)
            const Text('当前没有可显示的榜单'),
          if (feed.chartDirectoryError case final error?)
            Row(
              children: [
                Expanded(child: Text(error)),
                TextButton(
                  onPressed: () => feed.selectChartPlatform(
                    feed.chartPlatform,
                    refresh: true,
                  ),
                  child: const Text('重试榜单目录'),
                ),
              ],
            ),
        ],
      ],
    );
  }
}
