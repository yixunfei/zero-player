import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../data/source_repository.dart';
import '../domain/video_source.dart';

final class SourceFavoriteButton extends StatelessWidget {
  const SourceFavoriteButton({
    super.key,
    required this.source,
    required this.repository,
  });
  final VideoSource source;
  final SourceRepository repository;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: source.favorite ? '取消收藏渠道' : '收藏渠道',
    icon: Icon(source.favorite ? Icons.star : Icons.star_outline),
    color: source.favorite ? Theme.of(context).colorScheme.primary : null,
    onPressed: () => perform(
      context,
      () => repository.favorite(source.id, !source.favorite),
    ),
  );
}
