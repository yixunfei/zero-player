import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../catalog/data/provider_factory.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/domain/work_identity.dart';
import '../../discovery/data/catalog_discovery.dart';
import '../../library/data/history_repository.dart';
import '../../sources/data/source_repository.dart';
import '../../sources/domain/video_source.dart';

final class SearchController extends ChangeNotifier {
  SearchController(this.sources, this.network, this.history);
  final SourceRepository sources;
  final DocumentClient network;
  final HistoryRepository history;
  final items = <CatalogItem>[];
  final statuses = <String, String>{};
  final sourceNames = <String, String>{};
  final failedSources = <String>{};
  final latencies = <String, int>{};
  bool loading = false;
  String query = '';
  String? error;
  CancellationToken? _cancellation;
  int _generation = 0;

  Map<String, List<CatalogItem>> get groups => groupCatalogItems(items);
  final _seen = <String>{};
  final _blocked = <String>{};

  Future<void> search(
    String text, {
    bool filterAdult = true,
    int concurrency = 6,
    Set<String> excluded = const {},
  }) async {
    final work = _search(
      text,
      filterAdult: filterAdult,
      concurrency: concurrency.clamp(1, 16),
      excluded: excluded,
    );
    final generation = _generation;
    try {
      await work;
    } catch (_) {
      if (generation == _generation) {
        loading = false;
        error = '搜索未能完成，请检查本地存储和网络后重试';
        notifyListeners();
      }
    }
  }

  Future<void> _search(
    String text, {
    required bool filterAdult,
    required int concurrency,
    required Set<String> excluded,
  }) async {
    cancel();
    _blocked.clear();
    query = text.trim();
    if (query.isEmpty) {
      clear();
      return;
    }
    final generation = ++_generation;
    final token = CancellationToken();
    _cancellation = token;
    items.clear();
    _seen.clear();
    statuses.clear();
    sourceNames.clear();
    failedSources.clear();
    latencies.clear();
    error = null;
    loading = true;
    notifyListeners();
    await history.recordSearch(query);
    final enabled =
        (await sources.all())
            .where(
              (s) =>
                  s.available &&
                  !excluded.contains(s.id) &&
                  !_blocked.contains(s.id) &&
                  (!filterAdult || s.classification != 'adult'),
            )
            .toList()
          ..sort((a, b) {
            final failure = a.failures.compareTo(b.failures);
            return failure != 0
                ? failure
                : (a.latencyMs ?? 999999).compareTo(b.latencyMs ?? 999999);
          });
    if (generation != _generation) return;
    if (enabled.isEmpty) {
      error = '没有可用的已启用源，请先添加或启用来源';
      loading = false;
      notifyListeners();
      return;
    }
    for (final source in enabled) {
      statuses[source.id] = '排队中';
      sourceNames[source.id] = '${source.displayName} · ${source.description}';
    }
    var cursor = 0;
    final seconds = ((enabled.length / concurrency).ceil() * 10 + 10).clamp(
      30,
      300,
    );
    final deadline = Timer(Duration(seconds: seconds), token.cancel);
    Future<void> worker() async {
      while (cursor < enabled.length && !token.isCancelled) {
        final source = enabled[cursor++];
        if (!_blocked.contains(source.id)) {
          await _source(source, query, token, generation, filterAdult);
        }
      }
    }

    try {
      await Future.wait(
        List.generate(enabled.length.clamp(1, concurrency), (_) => worker()),
      );
    } finally {
      deadline.cancel();
      if (generation == _generation) {
        loading = false;
        if (token.isCancelled) {
          error = '搜索已达到时间上限，已保留收到的结果';
          statuses.updateAll(
            (id, status) =>
                status == '排队中' || status == '正在查询' ? '超过搜索时限' : status,
          );
        }
        notifyListeners();
      }
    }
  }

  Future<void> _source(
    VideoSource source,
    String query,
    CancellationToken parent,
    int generation,
    bool filterAdult,
  ) async {
    final token = CancellationToken();
    final remove = parent.listen(token.cancel);
    final timeout = Timer(const Duration(seconds: 10), token.cancel);
    var count = 0;
    final clock = Stopwatch()..start();
    try {
      statuses[source.id] = '正在查询';
      notifyListeners();
      final provider = createVodProvider(source, network, cancellation: token);
      var pages = 1;
      for (var page = 1; page <= pages; page++) {
        final result = await provider.search(query, page: page);
        if (generation != _generation ||
            parent.isCancelled ||
            _blocked.contains(source.id)) {
          return;
        }
        if (page == 1) latencies[source.id] = clock.elapsedMilliseconds;
        pages = result.pageCount.clamp(1, 5);
        for (final item in result.items) {
          if (filterAdult && adultContent('${item.title} ${item.category}')) {
            continue;
          }
          if (_seen.add('${item.sourceId}/${item.id}')) {
            items.add(item);
            count++;
          }
        }
        statuses[source.id] = '$count 条结果';
        notifyListeners();
      }
      await sources.health(source.id, null, latencyMs: latencies[source.id]);
      if (generation == _generation) {
        statuses[source.id] = count == 0 ? '无结果' : '$count 条结果';
      }
    } catch (e) {
      if (parent.isCancelled ||
          generation != _generation ||
          _blocked.contains(source.id)) {
        return;
      }
      final failure = token.isCancelled && !parent.isCancelled
          ? const RemoteFailure(FailureKind.timeout, '来源响应超时')
          : e is RemoteFailure
          ? e
          : const RemoteFailure(FailureKind.invalid, '来源数据解析失败');
      if (generation == _generation) {
        statuses[source.id] = failure.message;
        failedSources.add(source.id);
      }
      await sources.health(source.id, failure);
    } finally {
      timeout.cancel();
      remove();
      if (generation == _generation) notifyListeners();
    }
  }

  Future<void> blockSource(String id) async {
    _blocked.add(id);
    items.removeWhere((item) => item.sourceId == id);
    statuses[id] = '已屏蔽';
    failedSources.remove(id);
    notifyListeners();
    await sources.setEnabled(id, false);
  }

  void cancel() {
    _generation++;
    _cancellation?.cancel();
    loading = false;
    statuses.updateAll(
      (id, status) => status == '排队中' || status == '正在查询' ? '已取消' : status,
    );
  }

  void clear() {
    cancel();
    query = '';
    error = null;
    items.clear();
    _seen.clear();
    statuses.clear();
    sourceNames.clear();
    failedSources.clear();
    latencies.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
