import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/platform_services.dart';

/// Restores the shell's previous fullscreen state when a reader is removed.
class ReaderSystemUi {
  ReaderSystemUi(this.platform);

  static const _channel = MethodChannel('zero_player/platform');
  final PlatformServices? platform;
  bool _applied = false;

  void apply(bool immersive) {
    if (kIsWeb) return;
    _applied = true;
    unawaited(_set(immersive));
  }

  void restore() {
    if (!_applied) return;
    apply(platform?.appFullscreen.value ?? false);
  }

  Future<void> _set(bool immersive) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod<void>('setReaderImmersive', immersive);
        return;
      } on MissingPluginException {
        // The reader may be hosted without the application's Android activity.
      } on PlatformException {
        // Fall back to Flutter's system-bar handling if the native request fails.
      }
    } else if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(
      immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}
