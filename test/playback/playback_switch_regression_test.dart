import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import '../../test_support/fake_player_engine.dart';
import '../../test_support/http_test_server.dart';

late Directory root;
late AppServices services;
late FakePlayerEngine engine;
late PlaybackController player;
late HttpTestServer server;
late CatalogItem item;
const _position = Duration(seconds: 12);
final _quality = Uri.parse('https://media.example/episode1/high.m3u8');
Completer<void>? probeGate;

void main() {
  setUp(_initialize);
  tearDown(() async {
    if (probeGate != null && !probeGate!.isCompleted) probeGate!.complete();
    await player.close();
    await services.close();
    await server.close();
    await root.delete(recursive: true);
    probeGate = null;
  });
  test(
    'quality changes preserve user pause and suppress recovery while paused',
    () async {
      await player.seek(_position);
      await player.toggle();
      await player.changeQuality(_quality);
      expect(player.userPaused, isTrue);
      expect(engine.snapshot.playing, isFalse);
      expect(player.request!.position, _position);
      engine.failures.add('network');
      await Future<void>.delayed(Duration.zero);
      expect(player.recovering, isFalse);
    },
  );
  test('quality changes preserve an explicit recovery cancellation', () async {
    player.cancelRecovery();
    await player.changeQuality(_quality);
    engine.failures.add('network');
    await Future<void>.delayed(Duration.zero);
    expect(player.recovering, isFalse);
  });
  test(
    'new episodes and lines clear the previous episode quality URL',
    () async {
      await player.changeQuality(_quality);
      await player.select(0, 1);
      expect(player.request!.quality, isNull);
      await player.changeQuality(_quality);
      await player.select(1, 1);
      expect(player.request!.quality, isNull);
    },
  );
  test(
    'a superseded quality operation cannot pause the newly selected episode',
    () async {
      await player.toggle();
      final qualityChange = player.changeQuality(_quality);
      final newEpisode = player.select(0, 1);
      await Future.wait([qualityChange, newEpisode]);
      await Future<void>.delayed(Duration.zero);
      expect(player.request!.episode, 1);
      expect(engine.snapshot.playing, isTrue);
      expect(player.userPaused, isFalse);
    },
  );
  test(
    'switching episodes cancels in-flight alternative probes promptly',
    () async {
      probeGate = Completer<void>();
      final switching = player.switchAlternativeLine();
      for (var i = 0; i < 100 && server.calls['/alternate.mp4'] == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(server.calls['/alternate.mp4'], 1);
      await player.select(0, 1);
      final finished = await Future.any([
        switching.then((_) => true),
        Future<bool>.delayed(const Duration(milliseconds: 400), () => false),
      ]);
      expect(
        finished,
        isTrue,
        reason: 'obsolete HTTP probes must be cancelled',
      );
      expect(await switching, isFalse);
      expect(player.request!.episode, 1);
    },
  );
}

Future<void> _initialize() async {
  root = await Directory.systemTemp.createTemp('playback-switch-');
  server = await HttpTestServer.start((request) async {
    if (request.uri.path == '/alternate.mp4') await probeGate?.future;
    request.response.headers.contentType = ContentType('video', 'mp4');
    request.response.add([0, 0, 0, 24, 102, 116, 121, 112, 105, 115, 111, 109]);
  });
  services = AppServices.scoped(
    root,
    AppDatabase.memory(),
    allowPrivateNetworks: true,
  );
  await services.settings.load();
  await services.supervision.load();
  await services.settings.update({'contentFilter': false});
  await services.gateway.start();
  final source = await services.sources.saveManual('fixture', server.baseUri);
  item = CatalogItem(
    sourceId: source,
    id: 'movie',
    title: 'movie',
    lines: [
      for (final name in ['main', 'alternate'])
        PlayLine(name, [
          Episode('1', server.baseUri.resolve('$name.mp4')),
          Episode('2', server.baseUri.resolve('${name}2.mp4')),
        ]),
    ],
  );
  engine = FakePlayerEngine();
  player = PlaybackController(services, engine);
  await player.open(PlaybackRequest(item));
}
