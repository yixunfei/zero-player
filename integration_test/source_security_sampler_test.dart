import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/media/cache/segment_store.dart';
import 'package:zero_player/media/content_filter/ffmpeg_slice_sampler.dart';
import 'package:zero_player/media/gateway/media_gateway.dart';
import '../test_support/http_test_server.dart';
import '../test_support/fixture_project.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final name in ['sample.mp4', 'master.m3u8']) {
    testWidgets('restricted native sampler preserves $name', (tester) async {
      final project = fixtureProjectRoot();
      final root = await Directory.systemTemp.createTemp('security-sampler-');
      final upstream = await HttpTestServer.start(
        (request) => serveLocalFile(
          request,
          File(
            '$project/test_support/generated/${request.uri.pathSegments.join('/')}',
          ),
          contentType: 'application/octet-stream',
        ),
      );
      final gateway = MediaGateway(
        SegmentStore(Directory('${root.path}/cache')),
        allowPrivateNetworks: true,
      );
      await gateway.start();
      final session = gateway.createSession(HeaderPolicy({}));
      try {
        final input = await session.openMedia(upstream.baseUri.resolve(name));
        final sampler = FfmpegSliceSampler(
          isTrustedInput: gateway.isRegisteredResource,
          isPlaylist: gateway.isRegisteredPlaylist,
        );
        final token = CancellationToken();
        final duration = await sampler.duration(input, token);
        expect(duration.inSeconds, inInclusiveRange(11, 13));
        final slice = await sampler.sample(
          input,
          Duration.zero,
          const Duration(seconds: 4),
          Directory('${root.path}/sample'),
          token,
        );
        expect(slice.frames.length, inInclusiveRange(8, 10));
        expect(await slice.media.length(), greaterThan(0));
        expect(slice.audio, isNotNull);
        expect(gateway.failures, 0);
      } finally {
        session.close();
        await gateway.close();
        await upstream.close();
        await root.delete(recursive: true);
      }
    });
  }
}
