import '../../catalog/data/provider_factory.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/request_scheduler.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../sources/data/source_repository.dart';
import '../../../core/network/document_client.dart';
import '../data/download_repository.dart';
import '../domain/download_task.dart';

/// Resolve episode identity again when a paused task resumes. Unmatched cuts
/// or episodes are never substituted by list position.
Future<DownloadTask> resolveDownload(
  DownloadTask task,
  DownloadRepository downloads,
  SourceRepository sources,
  DocumentClient network,
  CancellationToken token,
) async {
  final sourceId = task.row['source_id'] as String?;
  final remoteId = task.row['remote_id'] as String?;
  if (sourceId == null || remoteId == null) return task;
  final source = await sources.find(sourceId);
  if (source == null || source.suppressed || !source.enabled) {
    throw const FormatException('原下载源已停用或移除');
  }
  final item = await createVodProvider(
    source,
    network,
    cancellation: token,
    priority: RequestPriority.background,
  ).detail(remoteId);
  final lines = item.lines.where((line) => line.name == task.row['line_name']);
  if (lines.length != 1) throw const FormatException('原下载线路已变化，请在详情中重新选择');
  final matches = matchingEpisodes(
    task.row['episode_label'] as String,
    lines.single.episodes,
  );
  if (matches.length != 1) throw const FormatException('下载剧集无法唯一匹配，请重新选择');
  final media = await createVodProvider(
    source,
    network,
    cancellation: token,
    priority: RequestPriority.background,
  ).resolve(lines.single.episodes[matches.single]);
  await downloads.relocate(task.id, media.uri, media.headers);
  return (await downloads.find(task.id))!;
}
