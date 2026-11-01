import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/music/application/music_multi_search.dart';
import 'package:zero_player/features/music/domain/music_track.dart';

void main() {
  test('bounded fan-out publishes fast results before slow sources', () async {
    final pending = <String, Completer<MusicSearchResult>>{};
    final published = <String>[];
    var active = 0, peak = 0;
    final runner = MusicMultiSearch((
      query, {
      page = 1,
      cancellation,
      provider = 'myfreemp3',
    }) async {
      active++;
      if (active > peak) peak = active;
      final done = pending[provider] = Completer<MusicSearchResult>();
      try {
        return await done.future;
      } finally {
        active--;
      }
    });
    final task = runner.run(
      'song',
      page: 2,
      cancellation: CancellationToken(),
      onResult: (source, response, failure) => published.add(source),
    );
    expect(pending.length, 3);
    pending['netease']!.complete(const MusicSearchResult([], hasNext: true));
    await Future<void>.delayed(Duration.zero);
    expect(published, ['netease']);
    expect(pending.length, 4);
    pending['myfreemp3']!.completeError(const FormatException('failed'));
    await Future<void>.delayed(Duration.zero);
    while (published.length < MusicMultiSearch.providers.length) {
      for (final item in pending.values.toList()) {
        if (!item.isCompleted) item.complete(const MusicSearchResult([]));
      }
      await Future<void>.delayed(Duration.zero);
    }
    await task;
    expect(peak, 3);
    expect(published.toSet(), MusicMultiSearch.providers.toSet());
  });

  test('deadline releases workers and cancels underlying requests', () async {
    var cancelled = 0;
    final failures = <Object>[];
    final runner = MusicMultiSearch((
      query, {
      page = 1,
      cancellation,
      provider = 'myfreemp3',
    }) {
      cancellation!.listen(() => cancelled++);
      return Completer<MusicSearchResult>().future;
    }, timeout: const Duration(milliseconds: 10));
    await runner.run(
      'song',
      page: 1,
      cancellation: CancellationToken(),
      onResult: (_, response, failure) => failures.add(failure!),
    );
    expect(cancelled, 6);
    expect(failures, everyElement(isA<TimeoutException>()));
  });

  test(
    'cancelled searches suppress late results and stop starting sources',
    () async {
      final token = CancellationToken();
      final pending = <Completer<MusicSearchResult>>[];
      var published = 0, cancelled = 0;
      final runner = MusicMultiSearch((
        query, {
        page = 1,
        cancellation,
        provider = 'myfreemp3',
      }) {
        cancellation!.listen(() => cancelled++);
        final done = Completer<MusicSearchResult>();
        pending.add(done);
        return done.future;
      });
      final task = runner.run(
        'old',
        page: 1,
        cancellation: token,
        onResult: (_, response, failure) => published++,
      );
      token.cancel();
      for (final done in pending) {
        done.complete(const MusicSearchResult([]));
      }
      await task;
      expect(cancelled, 3);
      expect(pending.length, 3);
      expect(published, 0);
    },
  );
}
