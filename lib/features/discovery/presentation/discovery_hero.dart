import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../app/poster_image.dart';
import '../../../app/synopsis_text.dart';
import '../data/recommendation_repository.dart';

final class DiscoveryHero extends StatelessWidget {
  const DiscoveryHero({
    super.key,
    required this.item,
    required this.onPlay,
    this.loadDescription,
  });
  final Recommendation item;
  final VoidCallback onPlay;
  final Future<String> Function()? loadDescription;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final narrow = bounds.maxWidth < 600;
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: PosterImage(url: item.poster, width: 960),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xee101219),
                      const Color(0x99101219),
                      const Color(0x44101219),
                    ],
                    stops: const [0, .55, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(narrow ? 24 : 36),
              child: Row(
                children: [
                  Expanded(child: _caption(context, narrow)),
                  if (!narrow) ...[
                    const SizedBox(width: 32),
                    SizedBox(
                      width: 180,
                      height: 250,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: PosterImage(url: item.poster, fit: BoxFit.cover),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _caption(BuildContext context, bool narrow) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'ZERO / CINEMA',
        style: TextStyle(
          color: Color(0xffd9b77b),
          fontSize: 12,
          letterSpacing: 3,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: narrow ? 28 : 40,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        item.subtitle.isEmpty ? '今晚，让故事占据屏幕。' : item.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70),
      ),
      if (item.description.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          item.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, height: 1.6),
        ),
      ],
      if (item.description.isEmpty && loadDescription != null) ...[
        const SizedBox(height: 12),
        SynopsisText(
          key: ValueKey(item.identity),
          load: loadDescription!,
          maxLines: 3,
          style: const TextStyle(color: Colors.white70, height: 1.6),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: onPlay,
        icon: const Icon(Icons.play_arrow),
        label: const Text('查看片源'),
      ),
    ],
  );
}
