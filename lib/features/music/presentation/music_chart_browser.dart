import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/poster_image.dart';
import '../data/music_catalog_api.dart';
import '../data/music_recommendations.dart';
import 'music_cards.dart';
import 'music_catalog_controls.dart';
import 'music_player.dart';

/// Full chart browser mirroring the source toplist page: grouped chart
/// navigation plus a ranked song list with trend, badges and duration.
final class MusicChartBrowser extends StatefulWidget {
  const MusicChartBrowser({
    super.key,
    required this.services,
    required this.onSearch,
  });
  final AppServices services;
  final ValueChanged<String> onSearch;

  @override
  State<MusicChartBrowser> createState() => _MusicChartBrowserState();
}

final class _MusicChartBrowserState extends State<MusicChartBrowser> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  MusicRecommendations get _feed => widget.services.musicRecommendations;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _feed,
      widget.services.contentPolicy,
    ]),
    builder: (context, _) => _body(context),
  );

  Widget _body(BuildContext context) {
    final feed = _feed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _platformBar(context, feed),
        if (feed.chartDirectoryLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(),
          ),
        if (feed.chartDirectoryError case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
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
          ),
        Expanded(
          child: feed.chart == 'wfu'
              ? _wfuList(feed)
              : feed.charts.isEmpty && !feed.chartDirectoryLoading
              ? const Center(child: Text('当前没有可显示的榜单'))
              : _browser(context, feed),
        ),
      ],
    );
  }

  Widget _platformBar(BuildContext context, MusicRecommendations feed) {
    final uri = feed.chartUri;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final entry in musicCatalogPlatforms.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: feed.chart != 'wfu' && feed.chartPlatform == entry.key,
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
          IconButton(
            tooltip: '刷新榜单曲目',
            onPressed: feed.loading
                ? null
                : () => feed.chart == 'wfu'
                ? feed.load('wfu', refresh: true)
                : feed.selectChartPlatform(feed.chartPlatform, refresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _browser(BuildContext context, MusicRecommendations feed) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final nav = MusicChartNav(
            options: feed.charts,
            selected: feed.selectedChart?.id,
            onSelected: feed.selectChart,
            compact: !wide,
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: nav,
                ),
                Expanded(child: _songList(feed)),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 220,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: nav,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _songList(feed)),
            ],
          );
        },
      );

  Widget _wfuList(MusicRecommendations feed) {
    final items = _visibleItems(feed);
    return CustomScrollView(
      key: const PageStorageKey('music-discovery'),
      slivers: [
        SliverToBoxAdapter(child: _header(feed)),
        MusicSongSliver(items: items, onSearch: widget.onSearch),
        if (feed.loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          ),
      ],
    );
  }

  Widget _songList(MusicRecommendations feed) {
    final items = _visibleItems(feed);
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.axis == Axis.vertical &&
            feed.hasMore &&
            !feed.loading &&
            metrics.pixels >= metrics.maxScrollExtent - 320) {
          unawaited(feed.loadMore());
        }
        return false;
      },
      child: CustomScrollView(
        key: const PageStorageKey('music-discovery'),
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: _header(feed)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ChartRow(
                  key: ValueKey('music-chart-row-$index'),
                  item: items[index],
                  onSearch: widget.onSearch,
                ),
                childCount: items.length,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _footer(feed, items.isEmpty)),
        ],
      ),
    );
  }

  List<MusicRecommendation> _visibleItems(MusicRecommendations feed) {
    final visible = feed.visible;
    return feed.items
        .where(
          (item) =>
              visible &&
              widget.services.contentPolicy.textAllowed(
                '${item.title} ${item.artist} ${item.description}',
              ),
        )
        .toList();
  }

  Widget _header(MusicRecommendations feed) {
    final selected = feed.selectedChart;
    final info = feed.chartInfo;
    final facts = [
      if (info?.updateTime.isNotEmpty ?? false) '更新 ${info!.updateTime}',
      if (info?.period.isNotEmpty ?? false) '期数 ${info!.period}',
      if (info?.updateTips.isNotEmpty ?? false) info!.updateTips,
      if (info?.listenNum case final listens?) '${musicPlayCount(listens)}播放',
      if (feed.total case final total?) '源站 $total 首',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selected != null || feed.chart == 'wfu')
            Text(
              feed.chart == 'wfu' ? 'WFU 音乐精选' : selected!.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          if (facts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                facts.join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (feed.notice != null || feed.pageError != null || !feed.visible)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                !feed.visible
                    ? '当前栏目已被过滤'
                    : (feed.pageError ?? feed.notice)!,
              ),
            ),
          if (feed.visible)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '已加载 ${feed.items.length} 首 · 点击曲目通过当前渠道搜索收听',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(MusicRecommendations feed, bool empty) {
    if (feed.loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('正在加载曲目…')),
      );
    }
    if (feed.hasMore && feed.visible) {
      return Center(
        child: TextButton(
          onPressed: feed.loadMore,
          child: Text(
            feed.pageError == null ? '加载更多曲目' : '重试下一页曲目',
          ),
        ),
      );
    }
    if (empty && feed.visible) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: TextButton(
            onPressed: () => feed.load(feed.chart, refresh: true),
            child: const Text('重新加载榜单曲目'),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

final class _ChartRow extends StatelessWidget {
  const _ChartRow({
    super.key,
    required this.item,
    required this.onSearch,
  });
  final MusicRecommendation item;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rank = item.rank;
    return InkWell(
      onTap: () => onSearch(item.query),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                rank == null ? '' : '$rank',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: rank != null && rank <= 3
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  fontWeight: rank != null && rank <= 3
                      ? FontWeight.w700
                      : null,
                ),
              ),
            ),
            _Trend(item: item),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 48,
                child: PosterImage(
                  url: item.cover,
                  width: 120,
                  showRetry: false,
                  placeholderIcon: Icons.album_outlined,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (item.vip) ...[
                        const SizedBox(width: 6),
                        MusicBadge(
                          text: 'VIP',
                          color: scheme.tertiaryContainer,
                          foreground: scheme.onTertiaryContainer,
                        ),
                      ],
                      if (item.mv) ...[
                        const SizedBox(width: 6),
                        MusicBadge(
                          text: 'MV',
                          color: scheme.secondaryContainer,
                          foreground: scheme.onSecondaryContainer,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (item.duration case final duration?)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  musicTime(duration),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _Trend extends StatelessWidget {
  const _Trend({required this.item});
  final MusicRecommendation item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = item.trendType;
    if (type == null) return const SizedBox(width: 52);
    final (IconData? icon, Color color, String label) = switch (type) {
      1 => (Icons.arrow_upward, scheme.primary, item.trendValue),
      2 => (Icons.arrow_downward, scheme.error, item.trendValue),
      6 => (Icons.arrow_upward, scheme.primary, item.trendValue),
      4 => (null, scheme.tertiary, '新'),
      5 => (null, scheme.secondary, '回'),
      _ => (Icons.remove, scheme.onSurfaceVariant, ''),
    };
    return SizedBox(
      width: 52,
      child: Row(
        children: [
          if (icon != null) Icon(icon, size: 14, color: color),
          if (label.isNotEmpty)
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}