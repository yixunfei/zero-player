import 'package:flutter/material.dart';
import '../domain/catalog_item.dart';
import '../../../app/poster_image.dart';

final class MovieHeader extends StatelessWidget {
  const MovieHeader({super.key, required this.item});
  final CatalogItem item;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final poster = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 150,
          height: 220,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: PosterImage(url: item.poster, width: 450),
          ),
        ),
      );
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title.isEmpty ? '未命名影片' : item.title,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text('${item.year}  ${item.area}  ${item.category}  ${item.remarks}'),
          const SizedBox(height: 16),
          Text(item.description.isEmpty ? '暂无简介' : item.description),
          const SizedBox(height: 16),
          Text(
            '演员：${item.actors.isEmpty ? '暂无资料' : item.actors}\n导演：${item.director.isEmpty ? '暂无资料' : item.director}',
          ),
        ],
      );
      if (constraints.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [poster, const SizedBox(height: 20), details],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          poster,
          const SizedBox(width: 28),
          Expanded(child: details),
        ],
      );
    },
  );
}
