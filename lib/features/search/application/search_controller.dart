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
  String? preferredSourceId;
  bool _filterAdult = true, _onlyPreferred = false;
  int _concurrency = 6;
  Set<String> _excluded = {};
  final _running = <String>{};
  Map<String, List<CatalogItem>>? _groupsCache;
  @override
  void notifyListeners() {
    _groupsCache = null;
    super.notifyListeners();
  }

  Map<String, List<CatalogItem>> get groups {
    if (_groupsCache != null) return _groupsCache!;
    final sorted = List<CatalogItem>.of(items)
      ..sort((a, b) {
        final rank = _rank(a.title).compareTo(_rank(b.title));
        if (rank != 0) return rank;
        final preferred = (a.sourceId == preferredSourceId ? 0 : 1).compareTo(
          b.sourceId == preferredSourceId ? 0 : 1,
        );
        if (preferred != 0) return preferred;
        final title = a.title.compareTo(b.title);
        return title != 0 ? title : a.sourceId.compareTo(b.sourceId);
      });
    return _groupsCache = groupCatalogItems(sorted);
  }

  int _rank(String title) {
    final name = title.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final term = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return name == term
        ? 0
        : name.startsWith(term)
        ? 1
        : name.contains(term)
        ? 2
        : 3;
  }

  int get completed =>
      statuses.values.where((s) => s != '排队中' && s != '正在查询').length -
      _running.where((id) => statuses[id] != '正在查询').length;
  final _seen = <String>{};
  final _blocked = <String>{};

  Future<void> search(
    String text, {
    bool filterAdult = true,
    int concurrency = 6,
    Set<String> excluded = const {},
    String? preferredSourceId,
    bool onlyPreferred = false,
  }) async {
    this.preferredSourceId = preferredSourceId;
    _filterAdult = filterAdult;
    _concurrency = concurrency.clamp(1, 16);
    _excluded = Set.of(excluded);
    _onlyPreferred = onlyPreferred;
    final work = _search(
      text,
      filterAdult: filterAdult,
      concurrency: concurrency.clamp(1, 16),
      excluded: excluded,
      onlyIds: onlyPreferred ? {?preferredSourceId} : null,
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

  Future<void> retryFailed() async {
    if (loading || failedSources.isEmpty || query.isEmpty) return;
    final ids = Set<String>.of(failedSources);
    if (_onlyPreferred) ids.removeWhere((id) => id != preferredSourceId);
    final work = _search(
      query,
      filterAdult: _filterAdult,
      concurrency: _concurrency,
      excluded: _excluded,
      onlyIds: ids,
      retainResults: true,
    );
    final generation = _generation;
    try {
      await work;
    } catch (_) {
      if (generation != _generation) return;
      loading = false;
      error = '重试未能完成，已保留收到的结果';
      notifyListeners();
    }
  }

  Future<void> _search(
    String text, {
    required bool filterAdult,
    required int concurrency,
    required Set<String> excluded,
    Set<String>? onlyIds,
    bool retainResults = false,
  }) async {
    cancel(notify: false);
    _blocked.clear();
    query = text.trim();
    if (query.isEmpty) {
      clear();
      return;
    }
    final generation = ++_generation;
    final token = CancellationToken();
    _cancellation = token;
    if (!retainResults) {
      items.clear();
      _seen.clear();
      statuses.clear();
      sourceNames.clear();
      failedSources.clear();
      latencies.clear();
    }
    error = null;
    loading = true;
    notifyListeners();
    await history.recordSearch(query);
    if (generation != _generation) return;
    final enabled =
        (await sources.all())
            .where(
              (s) =>
                  s.available &&
                  (onlyIds == null || onlyIds.contains(s.id)) &&
                  !excluded.contains(s.id) &&
                  !_blocked.contains(s.id) &&
                  (!filterAdult || s.classification != 'adult'),
            )
            .toList()
          ..sort((a, b) {
            final preferred = (a.id == preferredSourceId ? 0 : 1).compareTo(
              b.id == preferredSourceId ? 0 : 1,
            );
            if (preferred != 0) return preferred;
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
      failedSources.remove(source.id);
      sourceNames[source.id] = '${source.displayName} · ${source.description}';
    }
    await _runSources(enabled, token, generation, filterAdult, concurrency);
  }

  Future<void> _runSources(
    List<VideoSource> enabled,
    CancellationToken token,
    int generation,
    bool filterAdult,
    int concurrency,
  ) async {
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
          failedSources.addAll(
            enabled.map((s) => s.id).where((id) => statuses[id] == '超过搜索时限'),
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
    var count = items.where((i) => i.sourceId == source.id).length;
    var limited = false;
    final clock = Stopwatch()..start();
    try {
      statuses[source.id] = '正在查询';
      _running.add(source.id);
      notifyListeners();
      final provider = createVodProvider(source, network, cancellation: token);
      var pages = 1;
      for (var page = 1; page <= pages; page++) {
        final result = await provider.search(query, page: page);
        token.check();
        if (generation != _generation ||
            parent.isCancelled ||
            _blocked.contains(source.id)) {
          return;
        }
        if (page == 1) latencies[source.id] = clock.elapsedMilliseconds;
        pages = result.pageCount.clamp(1, 5);
        limited |= result.pageCount > 5;
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
        statuses[source.id] = count == 0
            ? '无结果'
            : '$count 条结果${limited ? '（前 5 页）' : ''}';
      }
    } catch (e) {
      if (parent.isCancelled &&
          generation == _generation &&
          !_blocked.contains(source.id)) {
        statuses[source.id] = '$count 条结果 · 超过搜索时限';
        failedSources.add(source.id);
      }
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
        statuses[source.id] = count == 0
            ? failure.message
            : '$count 条结果 · 后续分页未完成：${failure.message}';
        failedSources.add(source.id);
      }
      if (count == 0) await sources.health(source.id, failure);
    } finally {
      timeout.cancel();
      remove();
      if (generation == _generation) {
        _running.remove(source.id);
        notifyListeners();
      }
    }
  }

  Future<void> blockSource(String id) async {
    _blocked.add(id);
    _running.remove(id);
    items.removeWhere((item) => item.sourceId == id);
    statuses[id] = '已屏蔽';
    failedSources.remove(id);
    notifyListeners();
    await sources.setEnabled(id, false);
  }

  void cancel({bool notify = true}) {
    final wasLoading = loading;
    _generation++;
    _cancellation?.cancel();
    loading = false;
    statuses.updateAll((id, status) {
      if (status == '排队中' || _running.contains(id)) {
        failedSources.add(id);
        return '已取消（保留已收到的结果）';
      }
      return status;
    });
    _running.clear();
    if (wasLoading) error = '搜索已停止，已保留收到的结果';
    if (notify) notifyListeners();
  }

  void clear() {
    cancel(notify: false);
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
    cancel(notify: false);
    super.dispose();
  }
}
