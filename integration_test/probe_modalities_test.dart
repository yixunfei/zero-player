import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_inspector.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/sample_signature.dart';
import 'package:zero_player/media/content_filter/native_media_commands.dart';
import 'package:zero_player/media/content_filter/probe_sampler.dart';
import '../test_support/native_mark_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  for (final mode in [FeatureMode.visual, FeatureMode.audio]) {
    testWidgets(
      'mixed probe preserves ${mode.name} when the other track is absent',
      (tester) => _missingTrack(tester, mode),
    );
  }
}

Future<void> _missingTrack(WidgetTester tester, FeatureMode mode) async {
  final h = await NativeMarkHarness.create();
  final transport = h.services.gateway.createSession(HeaderPolicy({}));
  try {
    final file = 'only-${mode.name}.mp4';
    final token = CancellationToken();
    await NativeMediaCommands().run([
      '-i',
      '$fixtureProject/test_support/generated/content_filter/voice.mp4',
      '-map',
      mode == FeatureMode.visual ? '0:v:0' : '0:a:0',
      '-c',
      'copy',
      '${h.root.path}/$file',
    ], token);
    final input = await transport.openMedia(
      Uri.parse('http://127.0.0.1:${h.server.port}/$file'),
    );
    final sampler = ProbeSampler(
      trusted: h.services.gateway.isRegisteredResource,
      playlist: h.services.gateway.isRegisteredPlaylist,
      visual: true,
      audio: true,
    );
    final slice = await sampler.sample(
      input,
      const Duration(seconds: 4),
      const Duration(seconds: 4),
      Directory('${h.root.path}/probe'),
      token,
    );
    expect(slice.frames.isNotEmpty, mode == FeatureMode.visual);
    expect(slice.audio != null, mode == FeatureMode.audio);
    final signature = await sampleSignature(slice);
    final rule = FeatureRule(
      id: 'test',
      sourceId: 'channel',
      label: '内容',
      mode: mode,
      sampleMs: 4000,
      beforeMs: 0,
      afterMs: 0,
      visual: signature.visual,
      audio: signature.audio,
      thumbnail: '',
      originKey: 'different-episode',
      originStartMs: 0,
    );
    final inspector = FeatureInspector([rule]);
    try {
      await inspector.prepare(token);
      expect(
        (await inspector.inspect(slice, token)).verdict,
        FilterVerdict.block,
      );
    } finally {
      await inspector.close();
    }
  } finally {
    transport.close();
    await h.close(tester);
  }
}
