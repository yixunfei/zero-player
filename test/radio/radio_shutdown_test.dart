import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import 'package:zero_player/features/radio/application/radio_controller.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  group('connection interruption', _connectionTests);
  group('shutdown', _shutdownTests);
}

void _connectionTests() {
  test(
    'pause during connection retires the engine and resume reopens',
    () async {
      final blocked = _BlockedEngine();
      final ready = FakePlayerEngine();
      var count = 0;
      final controller = RadioController(() => count++ == 0 ? blocked : ready);
      addTearDown(controller.close);
      final opening = controller.select(_station('first'));
      await blocked.entered.future;
      await controller.pause();
      await opening;
      expect(blocked.disposed, isTrue);
      expect(controller.active, isTrue);
      expect(controller.loading, isFalse);
      expect(controller.playing, isFalse);
      await controller.toggle();
      expect(ready.opens, 1);
      expect(ready.snapshot.playing, isTrue);
      blocked.blocked.complete();
    },
  );

  test(
    'changing station interrupts a blocked open without stale playback',
    () async {
      final blocked = _BlockedEngine();
      final ready = FakePlayerEngine();
      var count = 0;
      final controller = RadioController(() => count++ == 0 ? blocked : ready);
      addTearDown(controller.close);
      final opening = controller.select(_station('first'));
      await blocked.entered.future;
      await controller.select(_station('second'));
      await opening;
      expect(blocked.disposed, isTrue);
      expect(controller.selected?.id, 'second');
      expect(ready.opens, 1);
      blocked.blocked.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.selected?.id, 'second');
      expect(controller.playing, isTrue);
    },
  );

  test('play after timeout opens a fresh engine', () async {
    final blocked = _BlockedEngine();
    final ready = FakePlayerEngine();
    var count = 0;
    final controller = RadioController(
      () => count++ == 0 ? blocked : ready,
      operationTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(controller.close);
    await controller.select(_station('retry'));
    expect(controller.error, contains('超时'));
    await controller.toggle();
    expect(controller.error, isNull);
    expect(ready.opens, 1);
    expect(ready.snapshot.playing, isTrue);
    blocked.blocked.complete();
  });
}

void _shutdownTests() {
  test('closing radio interrupts a never-ending native open', () async {
    final engine = _BlockedEngine();
    final controller = RadioController(() => engine);
    final opening = controller.select(
      LiveChannel(
        id: 'radio',
        listId: 'test',
        name: 'radio',
        urls: [Uri.parse('https://test.invalid/radio')],
      ),
    );
    await engine.entered.future;
    await controller.close().timeout(const Duration(seconds: 1));
    await opening.timeout(const Duration(seconds: 1));
    expect(engine.disposed, isTrue);
    expect(controller.active, isFalse);
    await controller.close();
    engine.blocked.complete();
  });

  test(
    'timed-out native open is retired before another engine can be used',
    () async {
      final engine = _BlockedEngine();
      final controller = RadioController(
        () => engine,
        operationTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(controller.close);
      await controller.select(
        LiveChannel(
          id: 'radio',
          listId: 'test',
          name: 'radio',
          urls: [Uri.parse('https://test.invalid/radio')],
        ),
      );
      expect(engine.disposed, isTrue);
      expect(controller.error, contains('超时'));
      engine.blocked.complete();
    },
  );
}

LiveChannel _station(String id) => LiveChannel(
  id: id,
  listId: 'test',
  name: id,
  urls: [Uri.parse('https://test.invalid/$id.mp3')],
);

final class _BlockedEngine implements PlayerEngine {
  final entered = Completer<void>();
  final blocked = Completer<void>();
  bool disposed = false;
  @override
  PlaybackSnapshot get snapshot => const PlaybackSnapshot();
  @override
  Stream<PlaybackSnapshot> get states => const Stream.empty();
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> open(Uri uri, {Map<String, String> headers = const {}}) {
    entered.complete();
    return blocked.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
