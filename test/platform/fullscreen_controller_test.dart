import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/platform/fullscreen_controller.dart';

void main() {
  test(
    'serializes rapid requests, ignores duplicate state and commits on completion',
    () async {
      final first = Completer<void>();
      final calls = <(bool, bool)>[];
      final controller = FullscreenController((app, player) async {
        calls.add((app, player));
        if (calls.length == 1) await first.future;
      });
      final enter = controller.setApplication(true);
      final duplicate = controller.setApplication(true);
      final leave = controller.setApplication(false);
      await Future<void>.delayed(Duration.zero);
      expect(calls, [(true, false)]);
      expect(controller.application.value, false);
      expect(controller.changing.value, true);
      first.complete();
      await Future.wait([enter, duplicate, leave]);
      expect(calls, [(true, false), (false, false)]);
      expect(controller.application.value, false);
      expect(controller.changing.value, false);
      await controller.dispose();
    },
  );

  test(
    'a native failure preserves state and later transitions can recover',
    () async {
      var fail = true;
      final controller = FullscreenController((app, player) async {
        if (fail) throw StateError('native failure');
      });
      await expectLater(controller.setApplication(true), throwsStateError);
      expect(controller.application.value, false);
      expect(controller.changing.value, false);
      fail = false;
      await controller.toggleApplication();
      expect(controller.application.value, true);
      await controller.dispose();
    },
  );

  test('application and player fullscreen remain independent', () async {
    final calls = <(bool, bool)>[];
    final controller = FullscreenController((app, player) async {
      calls.add((app, player));
    });
    await controller.setApplication(true);
    await controller.setPlayer(true);
    await controller.setPlayer(false);
    expect(controller.application.value, true);
    await controller.setApplication(false);
    expect(calls, [(true, false), (true, true), (true, false), (false, false)]);
    await controller.dispose();
  });
}
