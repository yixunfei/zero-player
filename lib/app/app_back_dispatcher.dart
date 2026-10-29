import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/platform/platform_services.dart';

/// Let the router close popups, drawers and pages before handling a root exit.
final class AppBackDispatcher extends RootBackButtonDispatcher {
  AppBackDispatcher({
    required this.router,
    required this.platform,
    required this.shutdown,
  });

  final GoRouter router;
  final PlatformServices platform;
  final Future<void> Function() shutdown;
  bool _dialogOpen = false;
  bool _exiting = false;

  @override
  Future<bool> invokeCallback(Future<bool> defaultValue) async {
    if (_exiting) return true;
    if (await super.invokeCallback(defaultValue)) return true;
    if (!platform.android) return false;
    if (router.state.uri.path != '/') {
      router.go('/');
    } else {
      unawaited(confirmExit());
    }
    return true;
  }

  Future<void> confirmExit() async {
    if (_dialogOpen || _exiting) return;
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _dialogOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.exit_to_app),
          title: const Text('退出 Zero Player？'),
          content: const Text('退出会停止播放和下载。观看记录会保留。'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续使用'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      _exiting = true;
      await shutdown();
      await SystemNavigator.pop();
    } finally {
      _dialogOpen = false;
      _exiting = false;
    }
  }
}
