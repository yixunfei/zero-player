import 'package:flutter/foundation.dart';

/// Serializes application/player requests and commits state only on success.
final class FullscreenController {
  FullscreenController(this.apply);
  final Future<void> Function(bool application, bool player) apply;
  final application = ValueNotifier(false);
  final changing = ValueNotifier(false);
  bool _player = false;
  Future<void> _queue = Future.value();

  Future<void> setApplication(bool enabled) => _schedule(application: enabled);
  Future<void> setPlayer(bool enabled) => _schedule(player: enabled);
  Future<void> toggleApplication() => _schedule(toggle: true);

  Future<void> _schedule({
    bool? application,
    bool? player,
    bool toggle = false,
  }) {
    final operation = _queue.then((_) async {
      final nextApp = toggle
          ? !this.application.value
          : application ?? this.application.value;
      final nextPlayer = player ?? _player;
      if (nextApp == this.application.value && nextPlayer == _player) return;
      changing.value = true;
      try {
        await apply(nextApp, nextPlayer);
        _player = nextPlayer;
        this.application.value = nextApp;
      } finally {
        changing.value = false;
      }
    });
    // A failed transition is returned to its caller, but must not poison later requests.
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> dispose() async {
    await _queue;
    application.dispose();
    changing.dispose();
  }
}
