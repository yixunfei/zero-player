import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'background_audio_session.dart';
import 'desktop_lifecycle.dart';

final class DesktopRadioTray {
  DesktopRadioTray(
    this.session,
    this.desktop, {
    this._channel = const MethodChannel('zero_player/radio_tray'),
  });
  final BackgroundAudioSession session;
  final DesktopLifecycle desktop;
  final MethodChannel _channel;
  Future<void> _pending = Future<void>.value();
  Future<void>? _disposing;
  String? _lastState;
  bool _disposed = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handle);
    session.addListener(_changed);
    desktop.keepInTray = _keepAlive;
    desktop.hideToTray = hide;
    await update();
  }

  bool _keepAlive() =>
      !_disposed && session.active && (session.playing || session.loading);
  void _changed() => unawaited(update().catchError(_report));

  Future<void> update() {
    if (_disposed) return Future<void>.value();
    final state = {
      'title': session.title,
      'active': session.active,
      'playing': session.playing,
      'loading': session.loading,
    };
    final signature = state.toString();
    if (_lastState == signature) return _pending;
    _lastState = signature;
    final next = _pending.then((_) async {
      if (!_disposed) await _channel.invokeMethod<void>('update', state);
    });
    _pending = next.catchError((Object _) {
      _lastState = null;
    });
    return next;
  }

  Future<void> hide() async {
    await update();
    if (!_keepAlive()) return;
    await _channel.invokeMethod<void>('hide');
  }

  Future<void> show() => _channel.invokeMethod<void>('show');

  Future<void> _handle(MethodCall call) async {
    if (_disposed) return;
    switch (call.method) {
      case 'toggle':
        await session.toggle();
      case 'stop':
        await session.stop();
      case 'exit':
        await desktop.closeWindow(force: true);
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    if (_initialized) session.removeListener(_changed);
    if (desktop.keepInTray == _keepAlive) desktop.keepInTray = null;
    if (desktop.hideToTray == hide) desktop.hideToTray = null;
    _channel.setMethodCallHandler(null);
    await _pending;
    if (_initialized) await _channel.invokeMethod<void>('dispose');
  }

  void _report(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'desktop radio tray',
    ),
  );
}
