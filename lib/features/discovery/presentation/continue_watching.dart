import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets.dart';
import '../../library/data/history_repository.dart';

final class ContinueWatching extends StatelessWidget {
  const ContinueWatching({super.key, required this.history});
  final Future<List<WatchEntry>> history;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<WatchEntry>>(
    future: history,
    builder: (context, snapshot) {
      final entries = snapshot.data ?? [];
      if (entries.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('继续观看', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final e = entries[i];
                  return SizedBox(
                    width: 240,
                    child: Card(
                      child: ListTile(
                        title: Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${e.episode} · ${clockText(e.position)}',
                        ),
                        trailing: const Icon(Icons.play_circle_outline),
                        onTap: () => context.push(
                          '/detail/${e.sourceId}/${Uri.encodeComponent(e.remoteId)}',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
