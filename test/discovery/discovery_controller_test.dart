import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/discovery/application/discovery_controller.dart';
import 'package:zero_player/features/discovery/data/recommendation_repository.dart';

void main() {
  _lifecycleTests();
  _paginationTests();
  _aggregationTests();
}

Recommendation item(String id) => Recommendation('作品$id', '', '', id: id);

void _lifecycleTests() {
  test(
    'reset cancels the previous channel and ignores its late result',
    () async {
      final controller = DiscoveryController();
      final old = Completer<Recommendations>();
      late CancellationToken oldToken;
      final first = controller.reset(
        categories: {'movie': '电影'},
        loader: (_, _, token) {
          oldToken = token;
          return old.future;
        },
      );
      await controller.reset(
        categories: {'movie': '电影'},
        loader: (_, _, _) async => Recommendations([item('new')]),
      );
      expect(oldToken.isCancelled, isTrue);
      old.complete(Recommendations([item('old')]));
      await first;
      expect(controller.sections.single.items.single.id, 'new');
      controller.dispose();
    },
  );
  test('disposal cancels work without late notifications', () async {
    final controller = DiscoveryController();
    final pending = Completer<Recommendations>();
    late CancellationToken token;
    var notifications = 0;
    controller.addListener(() => notifications++);
    final work = controller.reset(
      categories: {'a': 'A'},
      loader: (_, _, t) {
        token = t;
        return pending.future;
      },
    );
    controller.dispose();
    final count = notifications;
    pending.complete(Recommendations([item('late')]));
    await work;
    expect(token.isCancelled, isTrue);
    expect(notifications, count);
  });
  test('only one page request can run per feed', () async {
    final controller = DiscoveryController();
    final pending = Completer<Recommendations>();
    final calls = <int>[];
    await controller.reset(
      categories: {'a': 'A'},
      loader: (_, page, _) {
        calls.add(page);
        return page == 1
            ? Future.value(Recommendations([item('1')], hasMore: true))
            : pending.future;
      },
    );
    final next = controller.loadMore();
    await controller.loadMore();
    expect(calls, [1, 2]);
    pending.complete(Recommendations([item('1'), item('2')]));
    await next;
    expect(controller.count, 2);
    controller.dispose();
  });
}

void _paginationTests() {
  test(
    'automatic threshold preserves the page and manual loading continues',
    () async {
      final controller = DiscoveryController(maxItems: 10);
      var calls = 0;
      await controller.reset(
        categories: {'a': 'A'},
        loader: (_, page, _) async {
          calls++;
          return Recommendations(
            List.generate(8, (i) => item('$page-$i')),
            hasMore: true,
          );
        },
      );
      await controller.loadMore();
      await controller.loadMore();
      expect(controller.count, 16);
      expect(controller.atLimit, isTrue);
      expect(calls, 2);
      expect(controller.hasMore, isTrue);
      expect(controller.canLoadAutomatically, isFalse);
      await controller.loadMore(manual: true);
      expect(controller.count, 24);
      expect(calls, 3);
      expect(
        controller.sections.single.items.map((i) => i.id).toSet().length,
        24,
      );
      await controller.loadMore();
      expect(calls, 3);
      controller.dispose();
    },
  );
  test('a repeated page stops even when provider claims more pages', () async {
    final controller = DiscoveryController();
    await controller.reset(
      categories: {'a': 'A'},
      loader: (_, _, _) async => Recommendations([item('same')], hasMore: true),
    );
    await controller.loadMore();
    expect(controller.count, 1);
    expect(controller.hasMore, isFalse);
    controller.dispose();
  });
  test(
    'failure retains results and requires explicit retry of the same page',
    () async {
      final controller = DiscoveryController();
      var fail = true;
      final calls = <int>[];
      await controller.reset(
        categories: {'a': 'A'},
        loader: (_, page, _) async {
          calls.add(page);
          if (page == 2 && fail) throw StateError('offline');
          return Recommendations([item('$page')], hasMore: page < 2);
        },
      );
      await controller.loadMore();
      expect(controller.count, 1);
      expect(controller.canLoadAutomatically, isFalse);
      await controller.loadMore();
      fail = false;
      await controller.loadMore(retry: true);
      expect(calls, [1, 2, 2]);
      expect(controller.count, 2);
      controller.dispose();
    },
  );
  test(
    'a cached first page never silently mixes with live subsequent pages',
    () async {
      final controller = DiscoveryController();
      await controller.reset(
        categories: {'a': 'A'},
        loader: (_, _, _) async =>
            Recommendations([item('cached')], cached: true, hasMore: true),
      );
      expect(controller.hasMore, isFalse);
      controller.dispose();
    },
  );
}

void _aggregationTests() {
  test(
    'retry recovers category discovery before starting aggregation',
    () async {
      final controller = DiscoveryController();
      var failing = true;
      await controller.reset(
        aggregate: true,
        discoverCategories: true,
        categories: {'': '全部'},
        loader: (category, page, _) async {
          if (failing) throw StateError('offline');
          return category.isEmpty
              ? const Recommendations(
                  [],
                  categories: {'': '全部', '1': '电影', '2': '美剧'},
                )
              : Recommendations([item(category)]);
        },
      );
      expect(controller.hasFailures, isTrue);
      failing = false;
      await controller.loadMore(retry: true);
      expect(controller.sections.map((section) => section.category), [
        '1',
        '2',
      ]);
      controller.dispose();
    },
  );
  test(
    'aggregation uses two requests, all categories, stable rounds and deduplication',
    () async {
      final controller = DiscoveryController();
      var active = 0;
      var maxActive = 0;
      final calls = <String>[];
      await controller.reset(
        aggregate: true,
        categories: {'all': '全部', for (var i = 1; i <= 8; i++) '$i': '分类$i'},
        loader: (category, page, _) async {
          calls.add('$category:$page');
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return Recommendations([
            item('shared'),
            item(category),
          ], hasMore: true);
        },
      );
      await controller.loadMore();
      await controller.loadMore();
      expect(calls, ['1:1', '2:1', '3:1', '4:1', '5:1', '6:1']);
      expect(controller.count, 7);
      expect(maxActive, 2);
      expect(controller.sections.map((s) => s.category), [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
      ]);
      await controller.loadMore();
      expect(calls.skip(6), ['7:1', '8:1']);
      expect(controller.count, 9);
      controller.dispose();
    },
  );
  test('CMS bootstrap discovers categories before aggregating', () async {
    final controller = DiscoveryController();
    final calls = <String>[];
    await controller.reset(
      aggregate: true,
      discoverCategories: true,
      categories: {'': '全部'},
      loader: (category, page, _) async {
        calls.add(category);
        return category.isEmpty
            ? const Recommendations(
                [],
                categories: {'': '全部', '12': '电影', '99': 'AI剧场'},
              )
            : Recommendations([item(category)]);
      },
    );
    expect(calls, ['', '12', '99']);
    expect(controller.sections.map((s) => s.label), ['电影', 'AI剧场']);
    controller.dispose();
  });
}
