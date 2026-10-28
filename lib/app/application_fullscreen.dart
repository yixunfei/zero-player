import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/platform/platform_services.dart';
import 'widgets.dart';

/// App fullscreen is independent of the player's temporary theater state.
final class ApplicationFullscreen extends StatelessWidget {
  const ApplicationFullscreen({
    super.key,
    required this.platform,
    required this.child,
  });
  final PlatformServices platform;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: platform.appFullscreen,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): () =>
            perform(context, platform.toggleAppFullscreen),
        if (platform.appFullscreen.value)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              perform(context, () => platform.setAppFullscreen(false)),
      },
      child: Focus(autofocus: true, child: child),
    ),
  );
}

final class AppFullscreenButton extends StatelessWidget {
  const AppFullscreenButton({super.key, required this.platform});
  final PlatformServices platform;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      platform.appFullscreen,
      platform.fullscreenChanging,
    ]),
    builder: (context, _) {
      final full = platform.appFullscreen.value;
      return IconButton(
        tooltip: full ? '退出应用全屏 (F11)' : '应用全屏 (F11)',
        onPressed: platform.fullscreenChanging.value
            ? null
            : () => perform(context, platform.toggleAppFullscreen),
        icon: Icon(full ? Icons.fullscreen_exit : Icons.fullscreen),
      );
    },
  );
}
