import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/playback/application/playback_health.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';

void main() {
  _pauseAndProgressTests();
  _warningTests();
  testWidgets(
    'live startup and EOF trigger failover without waiting for VOD timeout',
    (tester) async {
      var stalled = 0;
      final health = PlaybackHealth(
        onStalled: () => stalled++,
        onProgress: () {},
      );
      health.observe(const PlaybackSnapshot(), enabled: true, live: true);
      await tester.pump(const Duration(seconds: 11));
      expect(stalled, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(stalled, 1);
      health.reset();
      health.observe(
        const PlaybackSnapshot(completed: true),
        enabled: true,
        live: true,
      );
      expect(stalled, 2);
      health.dispose();
    },
  );
}

void _pauseAndProgressTests() {
  testWidgets(
    'an engine pause without a toggle is never restarted by the watchdog',
    (tester) async {
      var stalled = 0;
      final health = PlaybackHealth(
        onStalled: () => stalled++,
        onProgress: () {},
      );
      health.observe(const PlaybackSnapshot(playing: true), enabled: true);
      health.observe(const PlaybackSnapshot(playing: false), enabled: true);
      await tester.pump(const Duration(minutes: 2));
      expect(stalled, 0);
      health.warn();
      await tester.pump(const Duration(seconds: 3));
      expect(
        stalled,
        1,
        reason: 'an actual native error still needs interruption handling',
      );
      health.dispose();
    },
  );
  testWidgets(
    'frequent small position updates keep a continuous stream healthy',
    (tester) async {
      var stalled = 0;
      final health = PlaybackHealth(
        onStalled: () => stalled++,
        onProgress: () {},
      );
      for (var i = 0; i < 1200; i++) {
        health.observe(
          PlaybackSnapshot(
            position: Duration(milliseconds: i * 50),
            playing: true,
          ),
          enabled: true,
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(stalled, 0);
      health.dispose();
    },
  );
}

void _warningTests() {
  testWidgets('repeated warnings cannot postpone interruption indefinitely', (
    tester,
  ) async {
    var stalled = 0;
    final health = PlaybackHealth(
      onStalled: () => stalled++,
      onProgress: () {},
    );
    health.observe(const PlaybackSnapshot(playing: true), enabled: true);
    for (var i = 0; i < 4; i++) {
      health.warn();
      await tester.pump(const Duration(seconds: 1));
    }
    expect(stalled, 1);
    health.dispose();
  });

  testWidgets('stalls are detected even without an emitted native error', (
    tester,
  ) async {
    var stalled = 0;
    final health = PlaybackHealth(
      onStalled: () => stalled++,
      onProgress: () {},
    );
    health.observe(
      const PlaybackSnapshot(playing: true, buffering: true),
      enabled: true,
    );
    await tester.pump(const Duration(seconds: 26));
    expect(stalled, 1);
    health.reset();
    health.observe(const PlaybackSnapshot(playing: false), enabled: false);
    health.warn();
    await tester.pump(const Duration(minutes: 2));
    expect(stalled, 1, reason: 'paused/background playback must not restart');
    health.dispose();
  });

  testWidgets('real progress cancels a warning, a clock reset does not', (
    tester,
  ) async {
    var stalled = 0;
    final health = PlaybackHealth(
      onStalled: () => stalled++,
      onProgress: () {},
    );
    health.observe(
      const PlaybackSnapshot(position: Duration(seconds: 12), playing: true),
      enabled: true,
    );
    health.warn();
    health.observe(
      const PlaybackSnapshot(position: Duration(seconds: 13), playing: true),
      enabled: true,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(stalled, 0);
    health.warn();
    health.observe(
      const PlaybackSnapshot(position: Duration(seconds: 1), playing: true),
      enabled: true,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(stalled, 1);
    health.dispose();
  });
}
