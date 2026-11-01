import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/poster_card.dart';
import '../data/music_recommendations.dart';
import '../data/music_collections.dart';

/// Music metadata discovery stays independent from the selected playback channel.
final class MusicDiscovery extends StatelessWidget {
  const MusicDiscovery({
    super.key,
    required this.services,
    required this.onSearch,
    required this.controls,
  });
  final AppServices services;
  final ValueChanged<String> onSearch;
  final Widget controls;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.musicRecommendations,
      services.contentPolicy,
    ]),
    builder: (context, _) {
      final feed = services.musicRecommendations;
      final items = feed.items
          .where(
            (i) => services.contentPolicy.textAllowed(
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
                final columns = (constraints.crossAxisExtent / 190)
                    .floor()
                    .clamp(2, 7);
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final width =
                    (constraints.crossAxisExtent - (columns - 1) * 12) /
                    columns;
                return SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = items[index];
                    return PosterCard(
                      key: ValueKey('music-recommendation-$index'),
                      title: item.title,
                      poster: item.cover,
                      subtitle: item.artist,
                      description: item.description.isEmpty
                          ? '点击封面，通过当前渠道搜索这首音乐。'
                          : item.description,
                      placeholderIcon: Icons.album_outlined,
                      informationLabel: '歌曲信息',
                      onTap: () => onSearch(item.query),
                    );
                  }, childCount: items.length),
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
          if (!feed.loading && items.isEmpty)
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
            const Text('从一张封面开始，找到今天想听的音乐。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in musicCategories)
                  ChoiceChip(
                    label: Text(category),
                    selected: feed.category == category,
                    onSelected: (_) => feed.load(
                      category == '榜单'
                          ? 'hot'
                          : musicCollections.entries
                                .firstWhere((e) => e.value.category == category)
                                .key,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chart
                    in (feed.category == '榜单'
                            ? musicCharts
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
                  onPressed: () => feed.load(feed.chart, refresh: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('点击封面后，通过当前音乐渠道搜索；推荐内容不指定播放来源。'),
            if (feed.loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (feed.notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(feed.notice!),
              ),
          ],
        ),
      ),
    ),
  ];
}
