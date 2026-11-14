import 'package:flutter/material.dart';
import '../../../app/poster_image.dart';
import '../data/music_style_catalog.dart';
import '../domain/music_recommendation.dart';

String musicPlayCount(int value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '$value';
}

/// Adaptive cover grid for discovery song metadata; tapping searches the
/// currently selected playback channel instead of embedding a stream.
final class MusicSongSliver extends StatelessWidget {
  const MusicSongSliver({
    super.key,
    required this.items,
    required this.onSearch,
  });
  final List<MusicRecommendation> items;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns =
            (constraints.crossAxisExtent / (144 * scale.clamp(1, 1.4)))
                .floor()
                .clamp(1, 7);
        final width = (constraints.crossAxisExtent - (columns - 1) * 12) /
            columns;
        return SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return _SongCard(
                key: ValueKey('music-recommendation-$index'),
                item: item,
                onSearch: onSearch,
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
  );
}

final class _SongCard extends StatelessWidget {
  const _SongCard({super.key, required this.item, required this.onSearch});
  final MusicRecommendation item;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onSearch(item.query),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(
                    url: item.cover,
                    placeholderIcon: Icons.album_outlined,
                  ),
                  if (item.rank != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: MusicBadge(
                        text: '#${item.rank}',
                        color: item.rank! <= 3
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        foreground: item.rank! <= 3
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                item.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class MusicBadge extends StatelessWidget {
  const MusicBadge({
    super.key,
    required this.text,
    required this.color,
    required this.foreground,
  });
  final String text;
  final Color color, foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Playlist cover card used by the category grid and homepage recommendation
/// row; shows creator and source play count like the platform website.
final class MusicPlaylistCard extends StatelessWidget {
  const MusicPlaylistCard({
    super.key,
    required this.list,
    required this.onTap,
    this.dense = false,
  });
  final MusicStylePlaylist list;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (list.creator.isNotEmpty) list.creator,
      if (list.plays case final plays?) '${musicPlayCount(plays)}播放',
      if (list.count case final count?) '$count首',
    ].join(' · ');
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: PosterImage(
                url: list.cover,
                placeholderIcon: Icons.library_music_outlined,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(10, dense ? 6 : 8, 10, 2),
              child: Text(
                list.name,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(10, 0, 10, dense ? 8 : 10),
              child: Text(
                subtitle.isEmpty ? '在线歌单' : subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

/// Adaptive playlist cover grid with the same column logic as song covers.
final class MusicPlaylistSliver extends StatelessWidget {
  const MusicPlaylistSliver({
    super.key,
    required this.lists,
    required this.onOpen,
  });
  final List<MusicStylePlaylist> lists;
  final ValueChanged<MusicStylePlaylist> onOpen;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns =
            (constraints.crossAxisExtent / (168 * scale.clamp(1, 1.4)))
                .floor()
                .clamp(1, 6);
        final width = (constraints.crossAxisExtent - (columns - 1) * 12) /
            columns;
        return SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) => MusicPlaylistCard(
              key: ValueKey('music-playlist-${lists[index].id}'),
              list: lists[index],
              onTap: () => onOpen(lists[index]),
            ),
            childCount: lists.length,
            addAutomaticKeepAlives: false,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            mainAxisExtent: width + 78 * scale,
          ),
        );
      },
    ),
  );
}