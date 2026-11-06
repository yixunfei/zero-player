import 'package:flutter/material.dart';
import '../application/playback_controller.dart';

/// A paused frame must be distinguishable from a stalled network request.
final class PlaybackStateOverlay extends StatelessWidget {
  const PlaybackStateOverlay({super.key, required this.controller});
  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.error != null || controller.blocked) {
      return const SizedBox.shrink();
    }
    final state = controller.state;
    final loading =
        controller.busy ||
        controller.awaitingResume ||
        (state.buffering && !controller.userPaused);
    if (loading) {
      return const IgnorePointer(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.playing || state.completed) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Semantics(
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pause_rounded, color: Colors.white, size: 48),
                  SizedBox(height: 4),
                  Text('已暂停', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
