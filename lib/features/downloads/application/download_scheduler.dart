import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/media_http_client.dart';
import '../../../media/cache/segment_fetcher.dart';
import '../../../media/gateway/offline_server.dart';
import '../../settings/application/settings_controller.dart';
import '../data/download_repository.dart';
import '../domain/download_task.dart';
import '../domain/download_location.dart';
import 'download_failover.dart';
import 'download_quota.dart';
import 'download_transfer.dart';

final class DownloadScheduler {
  DownloadScheduler(
    this.repository,
    this.fetcher,
    this.http,
    this.offline,
    this.settings, {
    this.isMetered,
    required this.validateMp4,
    this.resolve,
    this.failover,
  });
  final Future<void> Function(File, CancellationToken) validateMp4;
  final Future<bool> Function()? isMetered;
  final Future<DownloadTask> Function(DownloadTask, CancellationToken)? resolve;
  final DownloadFailover? failover;
  final DownloadRepository repository;
  final SegmentFetcher fetcher;
  final MediaHttpClient http;
  final OfflineServer offline;
  final SettingsController settings;
  final _tokens = <String, CancellationToken>{};
  final _jobs = <String, Future<void>>{};
  final _activeSources = <String, String>{};
  final _quota = DownloadQuota();
  Future<void>? _draining;
  bool _closed = false;
  bool _pendingKick = false;
  bool foreground = true;

  Future<void> initialize() => repository.recover();
  Future<void> resume(String id) async {
    if (_tokens.containsKey(id)) throw StateError('任务正在停止，请稍后继续');
    await repository.status(id, DownloadStatus.queued);
    kick();
  }

  Future<void> pause(String id) async {
    _tokens[id]?.cancel();
    await repository.status(id, DownloadStatus.paused);
  }

  void kick() {
    if (_closed) return;
    if (_draining != null) {
      _pendingKick = true;
      return;
    }
    _pendingKick = false;
    _draining = _drain().whenComplete(() {
      _draining = null;
      if (_pendingKick && !_closed) kick();
    });
    // Errors in an individual job are recorded on the task, rather than leaked
    // from a fire-and-forget UI action.
    unawaited(_draining!.catchError((Object _) {}));
  }

  Future<void> setForeground(bool value) async {
    foreground = value;
    if (!value && Platform.isAndroid) {
      for (final id in _tokens.keys.toList()) {
        await pause(id);
      }
    } else {
      kick();
    }
  }

  Future<void> _drain() async {
    final initial = await repository.all();
    _quota.initialize({for (final task in initial) task.id: task.bytes});
    while (!_closed && (foreground || !Platform.isAndroid)) {
      final all = await repository.all();
      final limit = settings.value.multiSourceDownload
          ? settings.value.downloadConcurrency
          : 1;
      for (final task in all.reversed) {
        if (_jobs.length >= limit || _closed) break;
        if (task.status != DownloadStatus.queued ||
            _jobs.containsKey(task.id)) {
          continue;
        }
        final job = _run(task);
        _jobs[task.id] = job.whenComplete(() {
          _jobs.remove(task.id);
        });
      }
      if (_jobs.isEmpty) break;
      await Future.any(_jobs.values.toList());
    }
    await Future.wait(_jobs.values.toList());
  }

  Future<void> _run(DownloadTask task) async {
    final token = CancellationToken();
    _tokens[task.id] = token;
    final sourceId = task.row['source_id'] as String? ?? '';
    final distribute =
        settings.value.multiSourceDownload &&
        _activeSources.containsValue(sourceId);
    _activeSources[task.id] = sourceId;
    try {
      final current = await repository.find(task.id);
      if (current == null ||
          current.status != DownloadStatus.queued ||
          token.isCancelled) {
        return;
      }
      await repository.status(task.id, DownloadStatus.running);
      if (!settings.value.allowMetered && (await isMetered?.call() ?? false)) {
        await repository.status(
          task.id,
          DownloadStatus.paused,
          error: '当前为计费网络，请在设置中允许下载',
        );
        return;
      }
      token.check();
      if (distribute && failover != null) {
        final alternative = await failover!.find(
          task,
          token,
          _activeSources.values.toSet(),
        );
        if (alternative != null) task = await _switch(task, alternative, token);
      }
      await _attempt(task, token);
    } catch (error) {
      final message = error is FormatException
          ? error.message
          : error is FileSystemException
          ? error.message
          : '下载失败，未找到可用的同作品同集来源；可手动重试';
      await repository.status(
        task.id,
        token.isCancelled ? DownloadStatus.paused : DownloadStatus.failed,
        error: token.isCancelled ? null : message,
      );
    } finally {
      _tokens.remove(task.id);
      _activeSources.remove(task.id);
    }
  }

  Future<void> _attempt(DownloadTask task, CancellationToken token) async {
    final tried = <String>{};
    for (var attempt = 0; attempt < 4; attempt++) {
      tried.add(task.row['source_id'] as String? ?? '');
      try {
        if (attempt == 0 && resolve != null) task = await resolve!(task, token);
        token.check();
        final limit = settings.value.downloadMiB * 1024 * 1024;
        await transferDownload(
          task: task,
          token: token,
          repository: repository,
          fetcher: fetcher,
          http: http,
          limit: limit,
          reserve: (bytes) => _quota.reserve(
            task.id,
            bytes,
            settings.value.downloadMiB * 1024 * 1024,
          ),
          validate: validateMp4,
        );
        return;
      } catch (error) {
        token.check();
        if (error is FileSystemException ||
            !settings.value.autoDownloadFallback ||
            failover == null ||
            attempt == 3) {
          rethrow;
        }
        await repository.status(
          task.id,
          DownloadStatus.running,
          error: '当前来源中断，正在寻找同作品同集的其他源',
        );
        final alternative = await failover!.find(task, token, tried);
        if (alternative == null) rethrow;
        task = await _switch(task, alternative, token);
      }
    }
  }

  Future<DownloadTask> _switch(
    DownloadTask task,
    DownloadLocation location,
    CancellationToken token,
  ) async {
    token.check();
    if (!repository.ownsPath(task.directory)) {
      throw const FileSystemException('下载路径无效');
    }
    final next = Directory(
      p.join(
        repository.root.path,
        '${task.id}-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await next.create(recursive: true);
    token.check();
    await repository.switchLocation(task.id, location, next.path);
    // Each source owns an independent attempt directory; no cross-source append.
    await fetcher.store.unpin(task.id);
    final old = Directory(task.directory);
    if (await old.exists()) await old.delete(recursive: true);
    _quota.release(task.id);
    _activeSources[task.id] = location.item.sourceId;
    return (await repository.find(task.id))!;
  }

  Future<void> remove(String id) async {
    if (offline.isPlaying(id)) throw StateError('请先停止此任务的离线播放或导出');
    if (_tokens.containsKey(id)) {
      await pause(id);
      throw StateError('正在停止任务，请稍后再次删除');
    }
    final task = await repository.find(id);
    if (task == null) return;
    if (!repository.ownsPath(task.directory)) throw StateError('任务路径不属于下载目录');
    await fetcher.store.unpin(id);
    final directory = Directory(task.directory);
    if (await directory.exists()) await directory.delete(recursive: true);
    await repository.remove(id);
    _quota.release(id);
  }

  Future<void> close() async {
    _closed = true;
    for (final token in _tokens.values) {
      token.cancel();
    }
    await _draining;
  }
}
