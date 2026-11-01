import 'package:flutter/foundation.dart';
import 'background_audio_session.dart';

/// The desktop tray controls whichever audio feature was most recently active.
final class BackgroundAudioGroup extends ChangeNotifier
    implements BackgroundAudioSession {
  BackgroundAudioGroup(this.sessions) {
    for (final session in sessions) {
      void changed() {
        if (session.active && (session.playing || session.loading)) {
          _current = session;
        }
        notifyListeners();
      }

      _listeners[session] = changed;
      session.addListener(changed);
    }
  }
  final List<BackgroundAudioSession> sessions;
  final _listeners = <BackgroundAudioSession, VoidCallback>{};
  BackgroundAudioSession? _current;
  BackgroundAudioSession? get current => _current?.active == true
      ? _current
      : sessions.where((session) => session.active).firstOrNull;
  @override
  bool get active => current?.active ?? false;
  @override
  bool get loading => current?.loading ?? false;
  @override
  bool get playing => current?.playing ?? false;
  @override
  String get title => current?.title ?? '';
  @override
  Future<void> toggle() async => current?.toggle();
  @override
  Future<void> stop() async => current?.stop();
  @override
  void dispose() {
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value);
    }
    super.dispose();
  }
}
