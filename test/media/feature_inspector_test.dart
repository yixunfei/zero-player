import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_inspector.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/sample_signature.dart';
import 'package:zero_player/media/hls/timeline.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('feature-'));
  tearDown(() async => root.delete(recursive: true));
  _provenanceTest(() => root);
  _fallbackTests(() => root);
}

void _provenanceTest(Directory Function() directory) {
  test(
    'manual and trailing keyword preserve independent boundaries and provenance',
    () async {
      final slice = await _sample(directory());
      final signature = await sampleSignature(slice, audio: false);
      final rule = FeatureRule(
        id: 'manual',
        sourceId: 'channel',
        label: '已标记片段',
        mode: FeatureMode.visual,
        sampleMs: 2000,
        beforeMs: 0,
        afterMs: 0,
        visual: signature.visual,
        audio: [],
        thumbnail: '',
        originKey: 'one',
        originStartMs: 0,
      );
      final inspector = FeatureInspector([
        rule,
      ], enhancement: _TrailingKeyword());
      final token = CancellationToken();
      await inspector.prepare(token);
      final result = await inspector.inspect(slice, token);
      expect(result.resolvedDetections, hasLength(2));
      expect(
        result.resolvedDetections.first.range.end,
        const Duration(seconds: 2),
      );
      expect(result.resolvedDetections.first.requiresConfirmation, isFalse);
      expect(result.resolvedDetections.last.requiresConfirmation, isTrue);
      expect(
        result.resolvedDetections.last.range.end,
        const Duration(milliseconds: 21500),
      );
      await inspector.close();
    },
  );
}

void _fallbackTests(Directory Function() directory) {
  for (final failure in ['prepare', 'inspect', 'uncertain']) {
    test('user feature still blocks when enhancement is $failure', () async {
      final slice = await _sample(directory());
      final signature = await sampleSignature(slice, audio: false);
      final rule = FeatureRule(
        id: 'marked-ad',
        sourceId: 'channel',
        label: '用户标记',
        mode: FeatureMode.visual,
        sampleMs: 2000,
        beforeMs: 0,
        afterMs: 4000,
        visual: signature.visual,
        audio: [],
        thumbnail: '',
        originKey: 'movie',
        originStartMs: 0,
      );
      final inspector = FeatureInspector([
        rule,
      ], enhancement: _UnavailableEnhancement(failure));
      final token = CancellationToken();
      await inspector.prepare(token);
      final result = await inspector.inspect(slice, token);
      expect(result.verdict, FilterVerdict.block);
      expect(result.reason, contains('用户标记'));
      expect(result.ranges.single.end, const Duration(seconds: 6));
      await inspector.close();
    });
  }

  test('enhancement failure without user rules remains explicit', () async {
    final inspector = FeatureInspector(
      [],
      enhancement: _UnavailableEnhancement('prepare'),
    );
    await expectLater(inspector.prepare(CancellationToken()), throwsStateError);
  });
  test('dense visual samples preserve enhanced OCR frame timing', () async {
    final root = directory();
    final original = await _sample(root);
    final frames = List.generate(8, (i) => File('${root.path}/$i.jpg'));
    final enhancement = _FrameInspector();
    final inspector = FeatureInspector(
      [],
      enhancement: enhancement,
      denseSampling: true,
    );
    final token = CancellationToken();
    await inspector.prepare(token);
    await inspector.inspect(
      MediaSlice(
        directory: root,
        media: original.media,
        frames: frames,
        audio: null,
        start: const Duration(seconds: 20),
        duration: const Duration(seconds: 2),
      ),
      token,
    );
    expect(enhancement.slice!.frames.map((f) => f.path), [
      frames[0].path,
      frames[2].path,
      frames[4].path,
      frames[6].path,
    ]);
    expect(enhancement.slice!.start, const Duration(seconds: 20));
    await inspector.close();
  });
}

final class _TrailingKeyword implements SliceInspector {
  @override
  Future<void> prepare(CancellationToken token) async {}
  @override
  Future<void> close() async {}
  @override
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken token,
  ) async => const FilterDecision(
    FilterVerdict.block,
    reason: '常见词',
    ranges: [
      RemovedInterval(
        Duration(milliseconds: 1500),
        Duration(milliseconds: 21500),
      ),
    ],
  );
}

final class _FrameInspector implements SliceInspector {
  MediaSlice? slice;
  @override
  Future<void> prepare(CancellationToken token) async {}
  @override
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken token,
  ) async {
    this.slice = slice;
    return const FilterDecision(FilterVerdict.allow);
  }

  @override
  Future<void> close() async {}
}

Future<MediaSlice> _sample(Directory root) async {
  final picture = img.Image(width: 32, height: 32);
  for (final pixel in picture) {
    final value = (pixel.x + pixel.y) % 8 < 4 ? 230 : 20;
    pixel.setRgb(value, value, value);
  }
  final frame = await File(
    '${root.path}/frame.png',
  ).writeAsBytes(img.encodePng(picture));
  return MediaSlice(
    directory: root,
    media: File('${root.path}/unused.ts'),
    frames: List.filled(4, frame),
    audio: null,
    start: Duration.zero,
    duration: const Duration(seconds: 2),
  );
}

final class _UnavailableEnhancement implements SliceInspector {
  _UnavailableEnhancement(this.failure);
  final String failure;
  @override
  Future<void> prepare(CancellationToken token) async {
    if (failure == 'prepare') throw StateError('optional runtime unavailable');
  }

  @override
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken token,
  ) async {
    if (failure == 'inspect') throw StateError('optional inspection failed');
    return const FilterDecision(FilterVerdict.uncertain);
  }

  @override
  Future<void> close() async {}
}
