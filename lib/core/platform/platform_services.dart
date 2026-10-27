import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'desktop_lifecycle.dart';
import 'fullscreen_controller.dart';

final class PlatformServices {
  PlatformServices({Future<void> Function(bool, bool)? applyFullscreen}) {
    _fullscreen = FullscreenController(applyFullscreen ?? _applyFullscreen);
  }
  static const _channel = MethodChannel('zero_player/platform');
  bool television = false;
  bool smallWindow = false;
  late final FullscreenController _fullscreen;
  ValueListenable<bool> get appFullscreen => _fullscreen.application;
  ValueListenable<bool> get fullscreenChanging => _fullscreen.changing;
  bool? _nativeFullscreen;
  Future<void> setAppFullscreen(bool enabled) =>
      _fullscreen.setApplication(enabled);
  Future<void> toggleAppFullscreen() => _fullscreen.toggleApplication();

  DesktopLifecycle? desktop;

  Future<void> initialize({File? windowState}) async {
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(const Size(720, 480));
      if (windowState != null) {
        desktop = DesktopLifecycle(windowState);
        await desktop!.initialize();
      }
    }
    if (Platform.isAndroid) {
      television = await _channel.invokeMethod<bool>('isTelevision') ?? false;
    }
  }

  Future<bool> isMetered() async => Platform.isAndroid
      ? await _channel.invokeMethod<bool>('isMetered') ?? true
      : false;

  Future<void> fullscreen(bool enabled) => _fullscreen.setPlayer(enabled);

  Future<void> _applyFullscreen(bool application, bool player) async {
    final enabled = application || player;
    if (Platform.isWindows) {
      if (_nativeFullscreen == enabled) return;
      // Let the current input/platform callback finish before native resize messages.
      await Future<void>.delayed(Duration.zero);
      // window_manager restores the style captured on entry, including WS_VISIBLE.
      // Capturing the hidden startup window makes it disappear on fullscreen exit.
      if (enabled) await _ensureWindowVisible();
      await windowManager.setFullScreen(enabled);
      _nativeFullscreen = enabled;
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      await SystemChrome.setPreferredOrientations(
        player
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : DeviceOrientation.values,
      );
    }
  }

  Future<void> dispose() async {
    desktop?.dispose();
    await _fullscreen.dispose();
  }

  Future<void> _ensureWindowVisible() async {
    if (await windowManager.isVisible()) return;
    await windowManager.show();
    final clock = Stopwatch()..start();
    // The Windows plugin uses ShowWindowAsync: the method reply is not visibility.
    while (!await windowManager.isVisible()) {
      if (clock.elapsed > const Duration(seconds: 2)) {
        throw StateError('窗口未能显示，请重试全屏切换');
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Rect? _previousBounds;
  Future<bool> pictureInPicture() async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('pictureInPicture') ?? false;
    }
    if (Platform.isWindows) {
      smallWindow = !smallWindow;
      if (smallWindow) _previousBounds = await windowManager.getBounds();
      await windowManager.setAlwaysOnTop(smallWindow);
      if (smallWindow) {
        await windowManager.setSize(const Size(720, 480));
      } else if (_previousBounds != null) {
        await windowManager.setBounds(_previousBounds!);
      }
      return true;
    }
    return false;
  }
}
