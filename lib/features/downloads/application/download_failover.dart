import 'dart:async';
import 'dart:convert';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/request_scheduler.dart';
import '../../catalog/data/provider_factory.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/domain/work_identity.dart';
import '../../settings/application/settings_controller.dart';
import '../../sources/data/source_repository.dart';
import '../domain/download_task.dart';
import '../domain/download_location.dart';

final class DownloadFailover {
  const DownloadFailover(this.sources, this.network, this.settings);
  final SourceRepository sources;
  final DocumentClient network;
  final SettingsController settings;

  CatalogItem _identity(Map row) => CatalogItem(
    sourceId: '',
    id: '',
    title: row['title'] as String,
    year: row['year'] as String? ?? '',
    category: row['category'] as String? ?? '',
    director: row['director'] as String? ?? '',
    remarks: row['remarks'] as String? ?? '',
  );

  Future<DownloadLocation?> find(
    DownloadTask task,
    CancellationToken parent,
    Set<String> excluded,
  ) async {
    final identity = task.row['work_json'] as String?;
    if (identity == null) return null;
    final row = jsonDecode(identity) as Map;
    final original = _identity(row);
    final candidates =
        (await sources.all())
            .where(
              (s) =>
                  s.available &&
                  !excluded.contains(s.id) &&
                  (!settings.value.filterAdult || s.classification != 'adult'),
            )
            .toList()
          ..sort(
            (a, b) => (a.latencyMs ?? 999999).compareTo(b.latencyMs ?? 999999),
          );
    final token = CancellationToken();
    final unlink = parent.listen(token.cancel);
    final deadline = Timer(const Duration(seconds: 45), token.cancel);
    DownloadLocation? found;
    var index = 0;
    Future<void> worker() async {
      while (index < candidates.length && !token.isCancelled && found == null) {
        final source = candidates[index++];
        final child = CancellationToken();
        final remove = token.listen(child.cancel);
        final timer = Timer(const Duration(seconds: 8), child.cancel);
        try {
          final provider = createVodProvider(
            source,
            network,
            cancellation: child,
            priority: RequestPriority.background,
          );
          final results = await provider.search(original.title);
          final matches = results.items
              .where((i) => sameDownloadWork(original, i))
              .toList();
          if (matches.length != 1) continue;
          final detail = await provider.detail(matches.single.id);
          if (!sameDownloadWork(original, detail)) continue;
          for (final line in detail.lines) {
            final episodes = matchingEpisodes(
              task.row['episode_label'] as String,
              line.episodes,
            );
            if (episodes.length != 1 ||
                !line.episodes[episodes.single].playable) {
              continue;
            }
            final media = await provider.resolve(
              line.episodes[episodes.single],
            );
            if (!token.isCancelled && found == null) {
              found = DownloadLocation(
                detail,
                line,
                Episode(line.episodes[episodes.single].label, media.uri),
                media.headers,
              );
              token.cancel();
            }
            break;
          }
        } catch (_) {
          if (parent.isCancelled) return;
        } finally {
          timer.cancel();
          remove();
        }
      }
    }

    try {
      await Future.wait(
        List.generate(
          candidates.length.clamp(
            0,
            settings.value.searchConcurrency.clamp(1, 4),
          ),
          (_) => worker(),
        ),
      );
      parent.check();
      return found;
    } finally {
      deadline.cancel();
      unlink();
    }
  }
}
