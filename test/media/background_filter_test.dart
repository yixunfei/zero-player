import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/media/content_filter/background_filter.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/hls/timeline.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('background-test-'),
  );
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  test(
    'missing capabilities fail open without sampling or leaked timers',
    () async {
      final statuses = <String>[];
      final worker = BackgroundFilter(
        input: Uri.parse('http://127.0.0.1/test'),
        directory: root,
        sample: (_, _, _, _, _) => throw StateError('must not sample'),
        inspector: _Inspector(fail: true),
        onStatus: statuses.add,
        onHit: (_) => fail('no hit'),
      );
      worker.begin();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(statuses.single, contains('继续播放'));
      await worker.close();
      expect(root.existsSync(), isFalse);
    },
  );
  test(
    'single analysis worker reports bounded ranges and pauses sampling',
    () async {
      var samples = 0, active = 0, maximum = 0;
      final hits = <RemovedInterval>[];
      final worker = BackgroundFilter(
        input: Uri.parse('http://127.0.0.1/test'),
        directory: root,
        sample: (_, start, duration, directory, token) async {
          samples++;
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          active--;
          return _slice(directory, start, duration);
        },
        inspector: _Inspector(),
        onStatus: (_) {},
        onHit: (hit) => hits.add(hit.range),
      );
      try {
        worker.begin();
        worker.observe(
          Duration.zero,
          const Duration(seconds: 30),
          playing: true,
          buffering: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(hits, hasLength(1));
        expect(hits.single.start, const Duration(seconds: 1));
        expect(hits.single.end, const Duration(seconds: 16));
        expect(maximum, 1);
        worker.observe(
          Duration.zero,
          const Duration(seconds: 30),
          playing: false,
          buffering: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(samples, 1);
      } finally {
        await worker.close();
      }
    },
  );
  _seekTests(() => root);
  _retryTests(() => root);
}

void _retryTests(Directory Function() directory) {
  test(
    'transient failure retries aligned samples and recovers detection',
    () async {
      final hit = Completer<void>();
      final starts = <Duration>[];
      final statuses = <String>[];
      final worker = BackgroundFilter(
        input: Uri.parse('http://127.0.0.1/test'),
        directory: directory(),
        start: const Duration(milliseconds: 1123),
        lookBehind: const Duration(seconds: 1),
        sample: (_, start, duration, directory, token) async {
          starts.add(start);
          if (starts.length == 1) {
            throw const FilterFailure('network interrupted');
          }
          return _slice(directory, start, duration);
        },
        inspector: _Inspector(),
        onStatus: statuses.add,
        onHit: (_) {
          if (!hit.isCompleted) hit.complete();
        },
      );
      try {
        worker.begin();
        worker.observe(
          const Duration(milliseconds: 1123),
          const Duration(seconds: 30),
          playing: true,
          buffering: false,
        );
        await hit.future.timeout(const Duration(seconds: 5));
        expect(starts.take(2), [Duration.zero, Duration.zero]);
        expect(statuses.any((s) => s.contains('自动重试')), isTrue);
        expect(statuses.any((s) => s.contains('已恢复')), isTrue);
        worker.seek(const Duration(milliseconds: 6723));
        worker.observe(
          const Duration(milliseconds: 6723),
          const Duration(seconds: 30),
          playing: true,
          buffering: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(starts.last, const Duration(milliseconds: 5500));
      } finally {
        await worker.close();
      }
    },
  );
}

void _seekTests(Directory Function() directory) {
  test(
    'seek ignores old snapshots until playback reaches the target',
    () async {
      final starts = <Duration>[];
      final worker = BackgroundFilter(
        input: Uri.parse('http://127.0.0.1/test'),
        directory: directory(),
        sample: (_, start, length, directory, _) async {
          starts.add(start);
          return _slice(directory, start, length);
        },
        inspector: _Inspector(),
        onStatus: (_) {},
        onHit: (_) {},
      );
      try {
        worker.begin();
        worker.seek(const Duration(minutes: 10));
        worker.observe(
          Duration.zero,
          const Duration(minutes: 30),
          playing: true,
          buffering: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 550));
        expect(
          starts,
          isEmpty,
          reason: 'old native events must not restart at zero',
        );
        worker.observe(
          const Duration(minutes: 10),
          const Duration(minutes: 30),
          playing: true,
          buffering: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 550));
        expect(starts.first, const Duration(minutes: 10));
      } finally {
        await worker.close();
      }
    },
  );
  test('seek discards a late result from the previous position', () async {
    final root = directory();
    final sampling = Completer<void>(), release = Completer<void>();
    var hits = 0;
    final worker = BackgroundFilter(
      input: Uri.parse('http://127.0.0.1/test'),
      directory: root,
      sample: (_, start, duration, directory, token) async {
        if (!sampling.isCompleted) sampling.complete();
        await release.future;
        return _slice(directory, start, duration);
      },
      inspector: _Inspector(),
      onStatus: (_) {},
      onHit: (_) => hits++,
    );
    try {
      worker.begin();
      worker.observe(
        Duration.zero,
        const Duration(seconds: 30),
        playing: true,
        buffering: false,
      );
      await sampling.future.timeout(const Duration(seconds: 3));
      worker.seek(const Duration(seconds: 20));
      worker.observe(
        const Duration(seconds: 20),
        const Duration(seconds: 30),
        playing: false,
        buffering: false,
      );
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(hits, 0);
    } finally {
      await worker.close();
    }
  });
}

MediaSlice _slice(Directory directory, Duration start, Duration length) =>
    MediaSlice(
      directory: directory,
      media: File('${directory.path}/unused'),
      frames: [],
      audio: null,
      start: start,
      duration: length,
    );

final class _Inspector implements SliceInspector {
  _Inspector({this.fail = false});
  final bool fail;
  @override
  Future<void> prepare(CancellationToken token) async {
    if (fail) throw const FilterFailure('unavailable');
  }

  @override
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken token,
  ) async => const FilterDecision(
    FilterVerdict.block,
    reason: 'keyword',
    ranges: [RemovedInterval(Duration(seconds: 1), Duration(seconds: 16))],
  );
  @override
  Future<void> close() async {}
}
