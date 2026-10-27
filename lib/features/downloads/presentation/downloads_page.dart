import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/platform/file_transfer.dart';
import '../../../media/export/media_exporter.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../playback/application/playback_controller.dart';
import '../domain/download_task.dart';

final class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key, required this.services});
  final AppServices services;
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

final class _DownloadsPageState extends State<DownloadsPage> {
  late Future<List<DownloadTask>> future;
  late final StreamSubscription<void> changes;
  @override
  void initState() {
    super.initState();
    _load();
    changes = widget.services.db.changes.listen((_) {
      if (mounted) setState(_load);
    });
  }

  void _load() {
    future = widget.services.downloads.all();
  }

  @override
  void dispose() {
    changes.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoadView(
    future: future,
    builder: (tasks) => tasks.isEmpty
        ? const EmptyState('还没有离线任务', '在影片详情点击“下载选集”，批量选择要保存的剧集')
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('Android 下载在前台执行。暂停、退出或断网后，已完成分片会保留。'),
              ),
              for (final task in tasks) _task(task),
            ],
          ),
  );
  Widget _task(DownloadTask task) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(task.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '${_status(task.status)} · ${(task.bytes / 1048576).toStringAsFixed(1)} MiB · ${task.completed} / ${task.total} 项',
          ),
          if (task.error != null) Text(task.error!),
          if (task.status == DownloadStatus.running)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (task.status == DownloadStatus.complete) ...[
                FilledButton.icon(
                  onPressed: () => _play(task),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('离线播放'),
                ),
                OutlinedButton(
                  onPressed: () => _export(task, ExportFormat.mp4),
                  child: const Text('导出 MP4'),
                ),
                OutlinedButton(
                  onPressed: () => _export(task, ExportFormat.ts),
                  child: const Text('导出 TS'),
                ),
              ] else if (task.status == DownloadStatus.running ||
                  task.status == DownloadStatus.queued)
                OutlinedButton(
                  onPressed: () => perform(
                    context,
                    () => widget.services.downloadScheduler.pause(task.id),
                  ),
                  child: const Text('暂停'),
                )
              else
                OutlinedButton(
                  onPressed: () => perform(
                    context,
                    () => widget.services.downloadScheduler.resume(task.id),
                  ),
                  child: const Text('继续 / 重试'),
                ),
              TextButton(
                onPressed: () async {
                  if (await confirm(context, '删除离线任务', '删除此任务及其独占媒体文件？') &&
                      mounted) {
                    await perform(
                      context,
                      () => widget.services.downloadScheduler.remove(task.id),
                    );
                  }
                },
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  String _status(DownloadStatus value) => switch (value) {
    DownloadStatus.queued => '排队中',
    DownloadStatus.running => '下载中',
    DownloadStatus.paused => '已暂停',
    DownloadStatus.failed => '失败，可恢复',
    DownloadStatus.complete => '已完成',
  };
  Future<void> _play(DownloadTask task) => perform(context, () async {
    final session = await widget.services.offline.open(
      task.id,
      Directory(task.directory),
      task.localPath!,
    );
    if (!mounted) {
      session.close();
      return;
    }
    context.push(
      '/player',
      extra: PlaybackRequest(
        CatalogItem(
          sourceId: 'offline',
          id: task.id,
          title: task.title,
          lines: [
            PlayLine('离线', [Episode(task.title, session.uri)]),
          ],
        ),
        offline: session,
      ),
    );
  });
  Future<void> _export(
    DownloadTask task,
    ExportFormat format,
  ) => perform(context, () async {
    final token = CancellationToken();
    final session = await widget.services.offline.open(
      task.id,
      Directory(task.directory),
      task.localPath!,
    );
    final file = File(
      p.join(
        widget.services.root.path,
        'export-${DateTime.now().microsecondsSinceEpoch}.${format.name}',
      ),
    );
    BuildContext? dialogContext;
    void closeDialog() {
      final current = dialogContext;
      if (current != null && current.mounted) Navigator.pop(current);
      dialogContext = null;
    }

    if (!mounted) {
      session.close();
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogContext = context;
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('正在导出媒体'),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 16),
                  Text('重封装完成并验证后，选择保存位置'),
                ],
              ),
              actions: [
                TextButton(onPressed: token.cancel, child: const Text('取消导出')),
              ],
            ),
          );
        },
      ),
    );
    try {
      await widget.services.exporter.export(
        session.uri,
        file.path,
        format,
        cancellation: token,
      );
      token.check();
      closeDialog();
      dialogContext = null;
      await FileTransfer.saveFile(
        file,
        '${task.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.${format.name}',
        format == ExportFormat.mp4 ? 'video/mp4' : 'video/mp2t',
      );
    } on RequestCancelled {
      if (mounted) message(context, '导出已取消');
    } finally {
      closeDialog();
      session.close();
      if (await file.exists()) await file.delete();
    }
  });
}
