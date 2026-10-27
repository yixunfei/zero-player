import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/discovery/application/discovery_controller.dart';
import 'package:zero_player/features/discovery/data/recommendation_repository.dart';

Recommendation _item(String id) => Recommendation(id, '', '', id: id);

void main() {
  test(
    'manual count uses pending page items without losing or duplicating',
    () async {
      final controller = DiscoveryController(maxItems: 20);
      addTearDown(controller.dispose);
      final calls = <int>[];
      await controller.reset(
        categories: {'a': 'A'},
        loader: (_, page, _) async {
          calls.add(page);
          return Recommendations(
            List.generate(20, (i) => _item('$page-$i')),
            hasMore: page < 4,
          );
        },
      );
      await controller.loadMore(manual: true, itemCount: 12);
      expect(controller.count, 32);
      expect(calls, [1, 2]);
      await controller.loadMore(manual: true, itemCount: 12);
      expect(controller.count, 44);
      expect(calls, [1, 2, 3]);
      await controller.loadMore(manual: true, itemCount: 12);
      expect(controller.count, 56);
      expect(calls, [1, 2, 3]);
      await controller.loadMore(manual: true, itemCount: 48);
      expect(controller.count, 80);
      expect(controller.hasMore, isFalse);
      expect(
        controller.sections.single.items.map((i) => i.id).toSet().length,
        80,
      );
    },
  );

  test(
    'aggregate manual count deduplicates across categories and pending',
    () async {
      final controller = DiscoveryController();
      addTearDown(controller.dispose);
      await controller.reset(
        aggregate: true,
        categories: {'a': 'A', 'b': 'B'},
        loader: (category, page, _) async => Recommendations([
          _item('shared-$page'),
          ...List.generate(10, (i) => _item('$category-$page-$i')),
        ], hasMore: true),
      );
      expect(controller.count, 21);
      await controller.loadMore(manual: true, itemCount: 12);
      expect(controller.count, 33);
      await controller.loadMore(manual: true, itemCount: 24);
      expect(controller.count, 57);
      final ids = controller.sections.expand((s) => s.items).map((i) => i.id);
      expect(ids.toSet().length, 57);
    },
  );

  test('reset discards pending and a late manual batch', () async {
    final controller = DiscoveryController();
    addTearDown(controller.dispose);
    final latePage = Completer<Recommendations>();
    await controller.reset(
      categories: {'old': 'old'},
      loader: (_, page, _) => page == 1
          ? Future.value(Recommendations([_item('old')], hasMore: true))
          : latePage.future,
    );
    final loading = controller.loadMore(manual: true, itemCount: 24);
    await controller.reset(
      categories: {'new': 'new'},
      loader: (_, _, _) async => Recommendations([_item('new')]),
    );
    latePage.complete(
      Recommendations(List.generate(50, (i) => _item('late-$i'))),
    );
    await loading;
    expect(controller.count, 1);
    expect(controller.sections.single.items.single.id, 'new');
    expect(controller.loading, isFalse);
  });
}
