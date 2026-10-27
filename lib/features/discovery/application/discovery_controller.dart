import 'package:flutter/foundation.dart';

import '../../../core/network/cancellation_token.dart';
import '../data/recommendation_repository.dart';

typedef DiscoveryLoader =
    Future<Recommendations> Function(
      String category,
      int page,
      CancellationToken token,
    );

final class DiscoverySection {
  const DiscoverySection(this.category, this.label, this.page, this.items);
  final String category;
  final String label;
  final int page;
  final List<Recommendation> items;
}

/// Owns a single homepage session. Late responses cannot cross reset/disposal.
/// Aggregation appends category pages in rounds, preserving scroll position.
final class DiscoveryController extends ChangeNotifier {
  DiscoveryController({this.maxItems = 240});
  final int maxItems;
  final List<DiscoverySection> _sections = [];
  List<DiscoverySection> get sections => List.unmodifiable(_sections);
  final _seen = <String>{};
  final _reserved = <String>{};
  final _pending = <DiscoverySection>[];
  final _cursors = <_CategoryCursor>[];
  CancellationToken _token = CancellationToken();
  DiscoveryLoader? _loader;
  Map<String, String> categories = {};
  bool aggregate = false;
  bool loading = false;
  bool _disposed = false;
  bool _bootstrapFailed = false;
  String? message;
  int get count => _seen.length;
  bool get atLimit => count >= maxItems;
  bool get hasFailures => _cursors.any((c) => c.failed);
  bool get canLoadAutomatically =>
      !loading &&
      !atLimit &&
      (_pending.isNotEmpty || _cursors.any((c) => !c.done && !c.failed));
  bool get hasMore => _pending.isNotEmpty || _cursors.any((c) => !c.done);
  bool _current(CancellationToken token) =>
      !_disposed && identical(token, _token) && !token.isCancelled;

  Future<void> reset({
    required DiscoveryLoader loader,
    required Map<String, String> categories,
    String category = '',
    bool aggregate = false,
    bool discoverCategories = false,
  }) async {
    _token.cancel();
    final token = _token = CancellationToken();
    _loader = loader;
    this.categories = Map.of(categories);
    this.aggregate = aggregate;
    _sections.clear();
    _seen.clear();
    _reserved.clear();
    _pending.clear();
    _cursors.clear();
    message = null;
    _bootstrapFailed = false;
    loading = true;
    notifyListeners();
    Recommendations? initial;
    if (discoverCategories) {
      try {
        initial = await loader('', 1, token);
        if (!_current(token)) return;
        this.categories = initial.categories.isEmpty
            ? {'': '全部'}
            : initial.categories;
      } catch (_) {
        if (!_current(token)) return;
        this.categories = {'': '全部'};
        _bootstrapFailed = true;
        _cursors.add(_CategoryCursor('', '全部')..failed = true);
        message = '频道暂不可用，请刷新或切换频道';
        loading = false;
        notifyListeners();
        return;
      }
    }
    _prepareCursors(category);
    if (initial != null && _cursors.length == 1 && _cursors.first.key == '') {
      _append(_cursors.first, initial);
      _flushPending();
      loading = false;
      notifyListeners();
    } else {
      loading = false;
      await loadMore();
    }
  }

  void _prepareCursors(String category) {
    if (aggregate) {
      final supported = categories.entries
          .where((e) => e.key != '' && e.key != 'all')
          .toList();
      for (final entry in supported) {
        _cursors.add(_CategoryCursor(entry.key, entry.value));
      }
    }
    if (_cursors.isEmpty) {
      final key = categories.containsKey(category)
          ? category
          : categories.keys.firstOrNull ?? '';
      _cursors.add(_CategoryCursor(key, categories[key] ?? '推荐'));
    }
  }

  Future<void> loadMore({
    bool retry = false,
    bool manual = false,
    int? itemCount,
  }) async {
    if (_disposed || loading || (atLimit && !manual) || _loader == null) return;
    if (retry && _bootstrapFailed) {
      return reset(
        loader: _loader!,
        categories: categories,
        aggregate: aggregate,
        discoverCategories: true,
      );
    }
    if (retry) {
      for (final c in _cursors) {
        c.failed = false;
      }
      message = null;
    }
    final token = _token;
    final target = manual && itemCount != null
        ? count + itemCount.clamp(12, 240)
        : null;
    loading = true;
    notifyListeners();
    try {
      for (var round = 0; round < 20; round++) {
        _flushPending(target == null ? null : target - count);
        if (target != null && count >= target) break;
        final ready = _cursors.where((c) => !c.done && !c.failed).toList()
          ..sort(
            (a, b) => a.page == b.page
                ? _cursors.indexOf(a).compareTo(_cursors.indexOf(b))
                : a.page.compareTo(b.page),
          );
        if (ready.isEmpty) break;
        final batch = ready.take(aggregate ? 2 : 1).toList();
        final results = await Future.wait(
          batch.map((cursor) async {
            try {
              return await _loader!(cursor.key, cursor.page, token);
            } catch (_) {
              return null;
            }
          }),
        );
        if (!_current(token)) return;
        for (var i = 0; i < batch.length; i++) {
          final result = results[i];
          if (result == null) {
            batch[i].failed = true;
            message = '部分内容加载失败，已保留当前列表，可手动重试';
          } else {
            _append(batch[i], result);
          }
        }
        _flushPending(target == null ? null : target - count);
        if (target == null || count >= target || hasFailures) break;
      }
    } finally {
      if (_current(token)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _flushPending([int? limit]) {
    var remaining = limit ?? 1 << 30;
    while (_pending.isNotEmpty && remaining > 0) {
      final section = _pending.removeAt(0);
      final take = section.items.length.clamp(0, remaining);
      final items = section.items.take(take).toList();
      _seen.addAll(items.map((item) => item.identity));
      if (!aggregate && _sections.isNotEmpty) {
        final first = _sections.removeAt(0);
        _sections.add(
          DiscoverySection(
            first.category,
            first.label,
            1,
            List.unmodifiable([...first.items, ...items]),
          ),
        );
      } else {
        _sections.add(
          DiscoverySection(
            section.category,
            section.label,
            section.page,
            List.unmodifiable(items),
          ),
        );
      }
      remaining -= take;
      if (take < section.items.length) {
        _pending.insert(
          0,
          DiscoverySection(
            section.category,
            section.label,
            section.page,
            section.items.sublist(take),
          ),
        );
      }
    }
  }

  void _append(_CategoryCursor cursor, Recommendations result) {
    if (result.categories.length > categories.length) {
      categories = result.categories;
    }
    if (result.message != null) message = result.message;
    if (result.items.isEmpty && result.message != null && !result.cached) {
      cursor.failed = true;
      return;
    }
    final unique = <Recommendation>[];
    var newForCategory = 0;
    for (final item in result.items) {
      if (cursor.seen.add(item.identity)) newForCategory++;
      if (_reserved.add(item.identity)) unique.add(item);
    }
    if (unique.isNotEmpty) {
      _pending.add(
        DiscoverySection(
          cursor.key,
          cursor.label,
          cursor.page,
          List.unmodifiable(unique),
        ),
      );
    }
    cursor.emptyPages = newForCategory == 0 ? cursor.emptyPages + 1 : 0;
    cursor.done =
        !result.hasMore ||
        result.cached ||
        (result.items.isNotEmpty && newForCategory == 0) ||
        cursor.emptyPages >= 2;
    cursor.page++;
  }

  @override
  void dispose() {
    _disposed = true;
    _token.cancel();
    _sections.clear();
    _seen.clear();
    _reserved.clear();
    _pending.clear();
    _cursors.clear();
    super.dispose();
  }
}

final class _CategoryCursor {
  _CategoryCursor(this.key, this.label);
  final String key;
  final String label;
  final seen = <String>{};
  int page = 1;
  int emptyPages = 0;
  bool done = false;
  bool failed = false;
}
