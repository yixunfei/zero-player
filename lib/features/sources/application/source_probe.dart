import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/request_scheduler.dart';
import '../../catalog/data/provider_factory.dart';
import '../data/source_repository.dart';
import '../domain/video_source.dart';
import 'source_metadata.dart';

final class SourceProbe extends ChangeNotifier {
  SourceProbe(this.repository, this.network);
  final SourceRepository repository;
  final DocumentClient network;
  CancellationToken? _token;
  final statuses = <String, String>{};
  bool running = false;
  bool _disposed = false;

  Future<void> run(
    List<VideoSource> sources, {
    int concurrency = 3,
    bool preserveStatuses = false,
  }) async {
    if (running || _disposed) return;
    final token = CancellationToken();
    _token = token;
    running = true;
    if (!preserveStatuses) statuses.clear();
    notifyListeners();
    var index = 0;
    Future<void> worker() async {
      while (!token.isCancelled && index < sources.length) {
        await _probe(sources[index++], token);
      }
    }

    try {
      await Future.wait(
        List.generate(
          sources.length.clamp(0, concurrency.clamp(1, 6)),
          (_) => worker(),
        ),
      );
    } finally {
      running = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _probe(VideoSource source, CancellationToken parent) async {
    final token = CancellationToken();
    final remove = parent.listen(token.cancel);
    final clock = Stopwatch();
    var apiSucceeded = false;
    statuses[source.id] = '${source.displayName} · 检测中';
    if (!_disposed) notifyListeners();
    try {
      final data = await createVodProvider(
        source,
        network,
        cancellation: token,
        priority: RequestPriority.background,
        onActivity: (active) => active ? clock.start() : clock.stop(),
      ).browse();
      clock.stop();
      token.check();
      apiSucceeded = true;
      await repository.health(
        source.id,
        null,
        latencyMs: clock.elapsedMilliseconds,
      );
      statuses[source.id] =
          '${source.displayName} · ${clock.elapsedMilliseconds} ms · API 可用';
      await updateSourceMetadata(
        source,
        data.metadata,
        repository,
        network,
        token,
      );
    } catch (e) {
      if (!parent.isCancelled && !_disposed) {
        final failure = token.isCancelled
            ? const RemoteFailure(FailureKind.timeout, '接口检测超时')
            : e is RemoteFailure
            ? e
            : const RemoteFailure(FailureKind.invalid, '接口格式无效');
        // Optional site metadata failure must not invalidate a successful API check.
        if (!apiSucceeded) {
          if (failure.kind != FailureKind.timeout) {
            await repository.health(
              source.id,
              failure,
              latencyMs: clock.elapsedMilliseconds,
            );
          }
          statuses[source.id] = failure.kind == FailureKind.timeout
              ? '${source.displayName} · 检测超时，仍可尝试使用'
              : '${source.displayName} · ${failure.message}';
        }
      }
    } finally {
      remove();
      if (!_disposed) notifyListeners();
    }
  }

  void cancel() => _token?.cancel();
  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
