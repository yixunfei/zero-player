import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Saves a normal window size and awaits pending progress before native close.
final class DesktopLifecycle with WindowListener {
  DesktopLifecycle(this.file);
  final File file;
  Future<void> Function()? beforeClose;
  Future<void> Function()? shutdown;
  bool Function()? keepInTray;
  Future<void> Function()? hideToTray;
  bool _closing = false;
  bool _listening = false;

  Future<void> initialize() async {
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    _listening = true;
    try {
      if (await file.exists()) {
        final state = jsonDecode(await file.readAsString()) as Map;
        final width = (state['width'] as num).toDouble().clamp(720.0, 3840.0);
        final height = (state['height'] as num).toDouble().clamp(480.0, 2160.0);
        await windowManager.setSize(Size(width, height));
        if (state['maximized'] == true) await windowManager.maximize();
      }
    } catch (_) {
      // A damaged optional window preference must not prevent app startup.
    }
  }

  Future<void> saveWindow() async {
    if (await windowManager.isFullScreen()) return;
    final maximized = await windowManager.isMaximized();
    final size = await windowManager.getSize();
    await file.writeAsString(
      jsonEncode({
        'width': maximized ? 1100 : size.width,
        'height': maximized ? 760 : size.height,
        'maximized': maximized,
      }),
      flush: true,
    );
  }

  @override
  void onWindowClose() => unawaited(closeWindow().catchError(_report));

  Future<void> closeWindow({bool force = false}) async {
    if (_closing) return;
    _closing = true;
    if (!force && keepInTray?.call() == true && hideToTray != null) {
      try {
        await saveWindow();
        await hideToTray!();
      } finally {
        _closing = false;
      }
      return;
    }
    for (final step in [beforeClose, saveWindow, shutdown]) {
      try {
        await step?.call();
      } catch (error, stack) {
        _report(error, stack);
      }
    }
    try {
      await windowManager.destroy();
    } catch (_) {
      _closing = false;
      if (!_listening) {
        windowManager.addListener(this);
        _listening = true;
      }
      rethrow;
    }
  }

  void _report(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'desktop shutdown',
    ),
  );

  void dispose() {
    windowManager.removeListener(this);
    _listening = false;
  }
}
