import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/media/content_filter/background_filter.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/hls/timeline.dart';

void main() {
  test(
    'background delivery retains keyword confirmation and reports expired hits',
    () async {
      final directory = await Directory.systemTemp.createTemp('delivery-');
      final delivered = Completer<FilterDetection>();
      final progress = Completer<String>();
      final worker = BackgroundFilter(
        input: Uri.parse('http://127.0.0.1/test'),
        directory: directory,
        sample: (_, start, length, work, token) async => MediaSlice(
          directory: work,
          media: File('${work.path}/unused'),
          frames: [],
          audio: null,
          start: start,
          duration: length,
        ),
        inspector: _MixedInspector(),
        onStatus: (_) {},
        onHit: (hit) {
          if (!delivered.isCompleted) delivered.complete(hit);
        },
        onDiagnostic: (text) {
          if (!progress.isCompleted) progress.complete(text);
        },
      );
      try {
        worker.begin();
        worker.observe(
          const Duration(seconds: 5),
          const Duration(seconds: 60),
          playing: true,
          buffering: false,
        );
        final hit = await delivered.future.timeout(const Duration(seconds: 3));
        expect(hit.source, DetectionSource.keyword);
        expect(hit.requiresConfirmation, isTrue);
        expect(hit.range.end, const Duration(seconds: 25));
        expect(await progress.future, contains('已播过 1 次'));
      } finally {
        await worker.close();
      }
    },
  );
}

final class _MixedInspector implements SliceInspector {
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
    detections: [
      FilterDetection(
        RemovedInterval(Duration.zero, Duration(seconds: 4)),
        '过期内容',
      ),
      FilterDetection(
        RemovedInterval(Duration(seconds: 5), Duration(seconds: 25)),
        '关键词',
        source: DetectionSource.keyword,
      ),
    ],
  );
}
