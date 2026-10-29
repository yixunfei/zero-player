import 'dart:async';
import 'package:flutter/material.dart';
import '../application/playback_controller.dart';

/// Status lifetime is independent of player controls, mouse movement and focus.
final class FilterPlaybackOverlay extends StatefulWidget {
  const FilterPlaybackOverlay({super.key, required this.controller});
  final PlaybackController controller;
  @override
  State<FilterPlaybackOverlay> createState() => _FilterPlaybackOverlayState();
}

final class _FilterPlaybackOverlayState extends State<FilterPlaybackOverlay> {
  Timer? _timer;
  String? _status;
  Object? _request;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _sync();
  }

  @override
  void didUpdateWidget(FilterPlaybackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _status = null;
    }
    _sync();
  }

  void _changed() {
    if (mounted) setState(_sync);
  }

  void _sync() {
    final player = widget.controller;
    if (_status != player.filterStatus || _request != player.request) {
      _timer?.cancel();
      _timer = null;
      _expired = false;
      _status = player.filterStatus;
      _request = player.request;
    }
    if (!_expired &&
        _timer == null &&
        _status != null &&
        player.state.playing &&
        !player.state.buffering &&
        !player.busy) {
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.controller;
    final hit = player.pendingFeature;
    final showStatus =
        !_expired &&
        _status != null &&
        player.state.playing &&
        !player.state.buffering &&
        !player.busy;
    if (hit == null && !showStatus) return const SizedBox.shrink();
    return Positioned(
      top: 64,
      left: 16,
      right: 60,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: hit == null
              ? IgnorePointer(
                  child: Text(
                    _status!,
                    key: const ValueKey('filter-status-toast'),
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hit.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: player.confirmFeatureSkip,
                          child: const Text('跳过此段'),
                        ),
                        TextButton(
                          onPressed: player.ignoreFeatureSkip,
                          child: const Text('本次忽略'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
