import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/playback/application/filter_detection_queue.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/hls/timeline.dart';

void main() {
  _overlappingFeatures();
  test(
    'keyword at ad tail cannot extend a manual boundary in either arrival order',
    () {
      for (final keywordFirst in [true, false]) {
        final queue = FilterDetectionQueue();
        final feature = _hit(10, 30), keyword = _hit(29, 49, keyword: true);
        for (final hit
            in keywordFirst ? [keyword, feature] : [feature, keyword]) {
          queue.add(hit);
        }
        expect(queue.at(const Duration(seconds: 29)), same(feature));
        queue.handle(feature);
        queue.add(keyword);
        expect(queue.at(const Duration(seconds: 31)), isNull);
      }
    },
  );
  test(
    'keyword requires confirmation and ignoring it cannot suppress content',
    () {
      final queue = FilterDetectionQueue();
      final keyword = _hit(29, 49, keyword: true);
      queue.add(keyword);
      expect(
        queue.at(const Duration(seconds: 30))!.requiresConfirmation,
        isTrue,
      );
      queue.handle(keyword);
      final feature = _hit(10, 35);
      queue.add(feature);
      expect(queue.at(const Duration(seconds: 30)), same(feature));
    },
  );
}

void _overlappingFeatures() {
  test('overlapping approved ranges preserve the uncovered tail', () {
    for (final reverse in [false, true]) {
      final queue = FilterDetectionQueue();
      final first = _hit(10, 20), second = _hit(15, 30);
      for (final hit in reverse ? [second, first] : [first, second]) {
        queue.add(hit);
      }
      expect(queue.at(const Duration(seconds: 10)), same(first));
      queue.handle(first);
      expect(queue.at(const Duration(seconds: 20)), same(second));
      queue.handle(second);
      expect(queue.at(const Duration(seconds: 30)), isNull);
    }
  });
  test('late approved overlap retains its tail after an earlier skip', () {
    final queue = FilterDetectionQueue();
    final first = _hit(10, 20), second = _hit(15, 30);
    queue.add(first);
    queue.handle(first);
    queue.add(second);
    expect(queue.at(const Duration(seconds: 20)), same(second));
    queue.handle(second);
    queue.add(_hit(16, 29));
    expect(queue.length, 0);
  });
}

FilterDetection _hit(int from, int to, {bool keyword = false}) =>
    FilterDetection(
      RemovedInterval(Duration(seconds: from), Duration(seconds: to)),
      keyword ? '常见词' : '手动内容',
      source: keyword ? DetectionSource.keyword : DetectionSource.feature,
    );
