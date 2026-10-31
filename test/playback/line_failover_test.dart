import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import '../../test_support/fake_player_engine.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'failover skips broken and ambiguous lines and preserves progress and pause',
    () async {
      final root = await Directory.systemTemp.createTemp('zero-failover-');
      final server = await HttpTestServer.start((request) {
        if (request.uri.path == '/bad.mp4') {
          request.response.statusCode = 404;
        } else {
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.add([
            0,
            0,
            0,
            24,
            102,
            116,
            121,
            112,
            105,
            115,
            111,
            109,
          ]);
        }
      });
      final services = AppServices.scoped(
        root,
        AppDatabase.memory(),
        allowPrivateNetworks: true,
      );
      await services.supervision.load();
      await services.settings.load();
      await services.settings.update({'contentFilter': false});
      await services.gateway.start();
      final sourceId = await services.sources.saveManual(
        'test',
        server.baseUri,
      );
      final engine = FakePlayerEngine();
      final player = PlaybackController(services, engine);
      addTearDown(() async {
        await player.close();
        await services.close();
        await server.close();
        await root.delete(recursive: true);
      });
      Episode ep(String label, String path) =>
          Episode(label, server.baseUri.resolve(path));
      final item = CatalogItem(
        sourceId: sourceId,
        id: 'm',
        title: 'Movie',
        lines: [
          PlayLine('current', [ep('EP1', 'main.mp4')]),
          PlayLine('ambiguous', [
            ep('第1集', 'wrong.mp4'),
            ep('1', 'wrong2.mp4'),
          ]),
          PlayLine('broken', [ep('1', 'bad.mp4')]),
          PlayLine('available', [ep('1', 'good.mp4')]),
        ],
      );
      await player.open(PlaybackRequest(item));
      await player.seek(const Duration(seconds: 12));
      await engine.setRate(1.5);
      await player.toggle();
      await Future<void>.delayed(Duration.zero);
      expect(await player.switchAlternativeLine(), isTrue);
      expect(player.request!.line, 3);
      expect(player.request!.position, const Duration(seconds: 12));
      expect(engine.snapshot.playing, isFalse);
      expect(engine.snapshot.rate, 1.5);
      expect(server.calls['/wrong.mp4'], isNull);
      expect(server.calls['/bad.mp4'], 1);
      expect(server.calls['/good.mp4'], 1);
    },
  );
}
