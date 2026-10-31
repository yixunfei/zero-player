import 'dart:io';
import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'desktop_lifecycle.dart';
import 'fullscreen_controller.dart';
import 'background_audio_session.dart';
import 'desktop_radio_tray.dart';

final class PlatformServices {
  PlatformServices({Future<void> Function(bool, bool)? applyFullscreen}) {
    _fullscreen = FullscreenController(applyFullscreen ?? _applyFullscreen);
  }
  static const _channel = MethodChannel('zero_player/platform');
  bool television = false;
  bool smallWindow = false;
  bool get mobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  bool get android => defaultTargetPlatform == TargetPlatform.android;
  late final FullscreenController _fullscreen;
  ValueListenable<bool> get appFullscreen => _fullscreen.application;
  ValueListenable<bool> get fullscreenChanging => _fullscreen.changing;
  bool? _nativeFullscreen;
  bool _appFullscreenAllowed = true;
  bool get appFullscreenAllowed => _appFullscreenAllowed;

  Future<void> configureAppFullscreen({required bool allowed}) {
    _appFullscreenAllowed = allowed;
    return allowed ? Future<void>.value() : _fullscreen.setApplication(false);
  }

  Future<void> setAppFullscreen(bool enabled) =>
      _fullscreen.setApplication(enabled && _appFullscreenAllowed);
  Future<void> toggleAppFullscreen() => _appFullscreenAllowed
      ? _fullscreen.toggleApplication()
      : _fullscreen.setApplication(false);

  DesktopLifecycle? desktop;
  DesktopRadioTray? radioTray;
  bool _disposed = false;

  Future<AppExitResponse> requestAppExit(
    Future<void> Function() shutdown,
  ) async {
    final lifecycle = desktop;
    if (lifecycle != null) {
      // Flutter can receive WM_CLOSE before window_manager. Let the same
      // lifecycle own both cleanup and destruction: closing services here
      // first removes the listener while preventClose is still enabled.
      await lifecycle.closeWindow();
      return AppExitResponse.cancel;
    }
    await shutdown();
    return AppExitResponse.exit;
  }

  Future<void> enableRadioTray(BackgroundAudioSession session) async {
    if (!Platform.isWindows || desktop == null || radioTray != null) return;
    radioTray = DesktopRadioTray(session, desktop!);
    await radioTray!.initialize();
  }

  Future<void> revealWindow() async {
    if (!Platform.isWindows) return;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

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

  Future<bool> isMetered() async {
    if (!Platform.isAndroid) return false;
    return queryMeteredConnection();
  }

  @visibleForTesting
  static Future<bool> queryMeteredConnection({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      return await _channel.invokeMethod<bool>('isMetered').timeout(timeout) ??
          true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    } on TimeoutException {
      return true;
    }
  }

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
      if (Platform.isAndroid && !enabled) {
        // Edge-to-edge changes inset layout but may retain immersive visibility.
        // Explicitly show both bars before restoring the application's layout.
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      }
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
    if (_disposed) return;
    _disposed = true;
    await _windowOperation(_restorePlayerWindow);
    await radioTray?.dispose();
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
  bool _previousOnTop = false;
  bool _previousMaximized = false;
  Future<void> _windowQueue = Future.value();

  Future<T> _windowOperation<T>(Future<T> Function() action) {
    final operation = _windowQueue.then((_) => action());
    _windowQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<bool> pictureInPicture() => _windowOperation(() async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('pictureInPicture') ?? false;
    }
    if (Platform.isWindows) {
      if (smallWindow) {
        await _restoreSmallWindow();
      } else {
        await _fullscreen.suspend();
        try {
          _previousOnTop = await windowManager.isAlwaysOnTop();
          _previousMaximized = await windowManager.isMaximized();
          smallWindow = true;
          if (_previousMaximized) await windowManager.unmaximize();
          _previousBounds = await windowManager.getBounds();
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setSize(const Size(720, 480));
        } catch (_) {
          await _restoreSmallWindow();
          rethrow;
        }
      }
      return true;
    }
    return false;
  });

  Future<void> restorePlayerWindow() =>
      _disposed ? Future.value() : _windowOperation(_restorePlayerWindow);

  Future<void> _restorePlayerWindow() async {
    await _fullscreen.setPlayer(false);
    if (Platform.isWindows && smallWindow) await _restoreSmallWindow();
  }

  Future<void> _restoreSmallWindow() async {
    await _fullscreen.suspend();
    try {
      if (smallWindow) {
        await windowManager.setAlwaysOnTop(_previousOnTop);
        if (_previousBounds != null) {
          await windowManager.setBounds(_previousBounds!);
        }
        if (_previousMaximized) await windowManager.maximize();
        smallWindow = false;
        _previousBounds = null;
      }
    } finally {
      await _fullscreen.resume();
    }
  }
}
