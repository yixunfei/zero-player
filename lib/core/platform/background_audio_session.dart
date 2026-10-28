import 'package:flutter/foundation.dart';

/// Narrow playback contract consumed by desktop integrations.
abstract interface class BackgroundAudioSession implements Listenable {
  String get title;
  bool get active;
  bool get playing;
  bool get loading;
  Future<void> toggle();
  Future<void> stop();
}
