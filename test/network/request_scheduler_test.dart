import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/request_scheduler.dart';

void main() {
  final a = Uri.parse('https://a.test');
  final b = Uri.parse('https://b.test');

  test('global and origin limits do not multiply concurrency', () async {
    final scheduler = RequestScheduler(globalLimit: 2, originLimit: 1);
    final first = await scheduler.acquire(a);
    var aGranted = false;
    final secondA = scheduler.acquire(a).then((p) {
      aGranted = true;
      return p;
    });
    final firstB = await scheduler.acquire(b);
    expect(aGranted, isFalse);
    first.release();
    final next = await secondA;
    expect(aGranted, isTrue);
    next.release();
    firstB.release();
    scheduler.close();
  });

  test(
    'playback precedes queued background work; releases are idempotent',
    () async {
      final scheduler = RequestScheduler(globalLimit: 1);
      final active = await scheduler.acquire(a);
      final background = scheduler.acquire(
        b,
        priority: RequestPriority.background,
      );
      final playback = scheduler.acquire(a, priority: RequestPriority.playback);
      active.release();
      active.release();
      final playing = await playback;
      playing.release();
      final later = await background;
      later.release();
      scheduler.close();
    },
  );

  test('cancel removes queued requests before they consume a permit', () async {
    final scheduler = RequestScheduler(globalLimit: 1);
    final active = await scheduler.acquire(a);
    final token = CancellationToken();
    final cancelled = scheduler.acquire(a, cancellation: token);
    final expected = expectLater(cancelled, throwsA(isA<RequestCancelled>()));
    token.cancel();
    await expected;
    active.release();
    final next = await scheduler.acquire(b);
    next.release();
    scheduler.close();
  });
}
