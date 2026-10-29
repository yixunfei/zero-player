import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  late Directory root;
  late AppServices services;
  late FakePlayerEngine engine;
  late PlaybackController player;
  final pending = <Completer<void>>[];
  final item = CatalogItem(
    sourceId: 'source',
    id: 'show',
    title: 'Show',
    lines: [
      PlayLine('main', [Episode('1', Uri.parse('https://example.org/1.mp4'))]),
    ],
  );
  setUp(() async {
    pending.clear();
    root = await Directory.systemTemp.createTemp('seek-sync-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.gateway.start();
    engine = FakePlayerEngine(
      onSeek: (_) {
        final complete = Completer<void>();
        pending.add(complete);
        return complete.future;
      },
    );
    player = PlaybackController(services, engine);
  });
  tearDown(() async {
    for (final complete in pending) {
      if (!complete.isCompleted) complete.complete();
    }
    await player.close();
    await services.close();
    await root.delete(recursive: true);
  });
  test(
    'history resume ignores stale marked positions until native acknowledgement',
    () async {
      await services.skips.add(
        'source|show|main|1',
        const Duration(seconds: 5),
        const Duration(seconds: 10),
        const Duration(seconds: 30),
        'must not override resume',
      );
      await player.open(
        PlaybackRequest(item, position: const Duration(seconds: 20)),
      );
      await _settle();
      engine.change(position: const Duration(seconds: 6));
      await _settle();
      expect(engine.seeks, [const Duration(seconds: 20)]);
      expect(player.state.position, Duration.zero);
      expect(player.canUndoSkip, isFalse);
      pending.single.complete();
      await _settle();
      expect(player.state.position, const Duration(seconds: 20));
    },
  );
  test(
    'rapid seeks serialize native commands and discard intermediate targets',
    () async {
      await player.open(PlaybackRequest(item));
      final first = player.seek(const Duration(seconds: 10));
      await _settle();
      final middle = player.seek(const Duration(seconds: 20));
      final last = player.seek(const Duration(seconds: 25));
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 30),
          duration: Duration(seconds: 30),
          completed: true,
        ),
      );
      await _settle();
      expect(engine.opens, 1);
      expect(player.state.position, Duration.zero);
      pending.first.complete();
      await first;
      await _settle();
      expect(engine.seeks, [
        const Duration(seconds: 10),
        const Duration(seconds: 25),
      ]);
      expect(player.state.position, Duration.zero);
      pending.last.complete();
      await Future.wait([middle, last]);
      await _settle();
      expect(player.state.position, const Duration(seconds: 25));
    },
  );
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));
