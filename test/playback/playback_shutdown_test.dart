import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';

void main() {
  test('shutdown can dispose an engine whose open never completes', () async {
    final root = await Directory.systemTemp.createTemp('playback-shutdown');
    final services = AppServices.scoped(
      root,
      AppDatabase.memory(),
      allowPrivateNetworks: true,
    );
    await services.gateway.start();
    final engine = _BlockedEngine();
    final player = PlaybackController(services, engine);
    addTearDown(() async {
      await player.close();
      await services.close();
      await root.delete(recursive: true);
    });
    final item = CatalogItem(
      sourceId: 'source',
      id: 'movie',
      title: 'movie',
      lines: [
        PlayLine('main', [
          Episode('1', Uri.parse('https://example.org/movie.mp4')),
        ]),
      ],
    );
    final opening = player.open(PlaybackRequest(item));
    await engine.entered.future;
    await player.close().timeout(const Duration(seconds: 1));
    await opening.timeout(const Duration(seconds: 1));
    expect(engine.disposed, isTrue);
    engine.blocked.complete();
    await Future<void>.delayed(Duration.zero);
  });
}

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
