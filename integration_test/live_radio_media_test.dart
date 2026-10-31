import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/m3u_parser.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/radio/application/radio_controller.dart';
import '../test_support/http_test_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets('real WAV and HLS media probe, scoped headers and radio failover', (
    tester,
  ) async {
    const project = String.fromEnvironment('PROJECT_ROOT');
    expect(project, isNotEmpty);
    final root = await Directory.systemTemp.createTemp('live-radio-');
    final services = AppServices.scoped(
      root,
      AppDatabase.memory(),
      allowPrivateNetworks: true,
    );
    final server = await HttpTestServer.start((request) async {
      if (request.uri.path == '/gone') {
        request.response.statusCode = 404;
        return;
      }
      if (request.headers.value('user-agent') != 'FixtureRadio' ||
          request.headers.value('referer') != 'https://radio.test/') {
        request.response.statusCode = 403;
        return;
      }
      final path = request.uri.path == '/radio.wav'
          ? 'radio.wav'
          : 'ts/${request.uri.pathSegments.last}';
      await serveLocalFile(
        request,
        File('$project/test_support/generated/$path'),
        contentType: path.endsWith('.m3u8')
            ? 'application/vnd.apple.mpegurl'
            : path.endsWith('.ts')
            ? 'video/mp2t'
            : 'audio/wav',
      );
    });
    try {
      await services.settings.load();
      await services.supervision.load();
      await services.gateway.start();
      await tester.pumpWidget(const SizedBox());
      for (final path in ['radio.wav', 'index.m3u8']) {
        final channel = parseM3u(
          '#EXTM3U\n#EXTINF:-1,测试广播\n#EXTVLCOPT:http-user-agent=FixtureRadio\n#EXTVLCOPT:http-referrer=https://radio.test/\n${server.baseUri}$path',
          server.baseUri,
          path,
        ).single;
        final result = await services.liveProbe.check(
          channel,
          CancellationToken(),
        );
        expect(result.availability, LiveAvailability.responding, reason: path);
      }
      final radio = services.radioPlayer;
      await radio.select(
        LiveChannel(
          id: 'fallback',
          listId: 'radio',
          name: '测试广播',
          urls: [
            server.baseUri.resolve('gone'),
            server.baseUri.resolve('radio.wav'),
          ],
          headers: const {
            'User-Agent': 'FixtureRadio',
            'Referer': 'https://radio.test/',
          },
        ),
      );
      for (
        var i = 0;
        i < 150 && !(radio.line == 1 && radio.playing && !radio.loading);
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(radio.line, 1);
      expect(radio.playing, isTrue);
      expect(radio.error, isNull);
      await _playHls(radio, server, tester);
      await radio.stop();
    } finally {
      await services.close();
      await server.close();
      await root.delete(recursive: true);
    }
  });
}

Future<void> _playHls(
  RadioController radio,
  HttpTestServer server,
  WidgetTester tester,
) async {
  await radio.select(
    LiveChannel(
      id: 'hls',
      listId: 'radio',
      name: 'HLS伴听',
      urls: [server.baseUri.resolve('index.m3u8')],
      headers: const {
        'User-Agent': 'FixtureRadio',
        'Referer': 'https://radio.test/',
      },
    ),
  );
  for (
    var i = 0;
    i < 100 && (server.calls['/segment-000.ts'] == null || !radio.playing);
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(server.calls['/segment-000.ts'], greaterThan(0));
  expect(radio.playing, isTrue);
  expect(radio.error, isNull);
}
