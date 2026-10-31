import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/radio/application/radio_controller.dart';
import '../../test_support/fake_player_engine.dart';

LiveChannel station(String name) => LiveChannel(
  id: name,
  listId: 'radio',
  name: name,
  urls: [Uri.parse('https://example.com/$name.mp3')],
);

void main() {
  test('close during native setup prevents a late stream open', () async {
    final entered = Completer<void>();
    final unblock = Completer<void>();
    final engine = FakePlayerEngine(
      onVolume: (_) {
        entered.complete();
        return unblock.future;
      },
    );
    final controller = RadioController(() => engine);
    final opening = controller.select(station('stale'));
    await entered.future;
    final closing = controller.close();
    unblock.complete();
    await Future.wait([opening, closing]);
    expect(engine.opens, 0);
  });
  test(
    'rapid station changes discard stale opens and support pause/stop',
    () async {
      final engine = FakePlayerEngine();
      final replacement = FakePlayerEngine();
      var created = false;
      final controller = RadioController(() {
        if (created) return replacement;
        created = true;
        return engine;
      });
      addTearDown(controller.close);
      final first = controller.select(station('first'));
      final last = controller.select(station('last'));
      await Future.wait([first, last]);
      await Future<void>.delayed(Duration.zero);
      expect(engine.opens, 1);
      expect(controller.selected?.name, 'last');
      expect(controller.playing, isTrue);
      await controller.toggle();
      await Future<void>.delayed(Duration.zero);
      expect(controller.playing, isFalse);
      engine.failures.add('raw internal native error');
      await Future<void>.delayed(Duration.zero);
      expect(controller.error, contains('暂时无法播放'));
      await controller.select(station('retry'));
      expect(replacement.opens, 1);
      expect(controller.error, isNull);
      await controller.stop();
      expect(controller.loading, isFalse);
    },
  );

  test(
    'leaving immediately discards pending initialization and playback',
    () async {
      var created = false;
      final controller = RadioController(() {
        created = true;
        return FakePlayerEngine();
      });
      final pending = controller.select(station('cancelled'));
      await controller.close();
      await pending;
      expect(created, isFalse);
      await controller.select(station('closed'));
      expect(created, isFalse);
    },
  );
}
