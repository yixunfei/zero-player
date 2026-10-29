import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/platform/platform_services.dart';
import 'widgets.dart';
import 'app_layout.dart';

/// App fullscreen is independent of the player's temporary theater state.
final class ApplicationFullscreen extends StatefulWidget {
  const ApplicationFullscreen({
    super.key,
    required this.platform,
    required this.child,
  });
  final PlatformServices platform;
  final Widget child;

  @override
  State<ApplicationFullscreen> createState() => _ApplicationFullscreenState();
}

final class _ApplicationFullscreenState extends State<ApplicationFullscreen> {
  bool? _allowed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = !usesCompactNavigation(context, widget.platform);
    if (_allowed == allowed) return;
    _allowed = allowed;
    unawaited(widget.platform.configureAppFullscreen(allowed: allowed));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.platform.appFullscreen,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): () {
          if (widget.platform.appFullscreenAllowed) {
            perform(context, widget.platform.toggleAppFullscreen);
          }
        },
        if (widget.platform.appFullscreen.value)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              perform(context, () => widget.platform.setAppFullscreen(false)),
      },
      child: Focus(autofocus: true, child: widget.child),
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
      if (usesCompactNavigation(context, platform)) {
        return const SizedBox.shrink();
      }
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
