import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/widgets.dart';
import '../application/playback_controller.dart';

final class PlaybackSurface extends StatefulWidget {
  const PlaybackSurface({
    super.key,
    required this.controller,
    required this.video,
    required this.transport,
    required this.title,
    required this.onBack,
    required this.onOptions,
    required this.locked,
    required this.onLock,
    required this.gestures,
    this.errorAction,
  });
  final PlaybackController controller;
  final Widget video;
  final Widget transport;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onOptions;
  final bool locked;
  final ValueChanged<bool> onLock;
  final bool gestures;
  final Widget? errorAction;
  @override
  State<PlaybackSurface> createState() => _PlaybackSurfaceState();
}

final class _PlaybackSurfaceState extends State<PlaybackSurface> {
  bool visible = true;
  bool interacting = false;
  bool controlsFocused = false;
  bool _keyboardInput = false;
  final _surfaceFocus = FocusNode();
  Timer? timer;
  Duration? seekPreview;
  Duration seekStart = Duration.zero;
  double dragX = 0, dragY = 0, baseVolume = 0, shade = 0, baseShade = 0;
  bool volumeSide = true;
  String? hint;
  bool get canGesture => !widget.locked && widget.gestures;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _arm();
  }

  @override
  void dispose() {
    timer?.cancel();
    _surfaceFocus.dispose();
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!widget.controller.state.playing || widget.controller.error != null) {
      timer?.cancel();
      if (!visible && mounted) setState(() => visible = true);
    } else if (!(timer?.isActive ?? false) && visible && !interacting) {
      _arm();
    }
  }

  void _arm() {
    timer?.cancel();
    if (!widget.controller.state.playing ||
        interacting ||
        (controlsFocused && _keyboardInput)) {
      return;
    }
    timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _surfaceFocus.requestFocus();
        setState(() => visible = false);
      }
    });
  }

  void _show() {
    if (!visible) setState(() => visible = true);
    _arm();
  }

  void _tap() {
    _surfaceFocus.requestFocus();
    setState(() => visible = !visible);
    _arm();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _surfaceFocus,
    autofocus: true,
    onKeyEvent: _onKey,
    child: _surface(),
  );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _keyboardInput = true;
      final wasHidden = !visible;
      _show();
      if (wasHidden &&
          !widget.locked &&
          {
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.select,
            LogicalKeyboardKey.enter,
          }.contains(event.logicalKey)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) FocusScope.of(context).nextFocus();
        });
        return KeyEventResult.handled;
      }
      if (_surfaceFocus.hasPrimaryFocus &&
          !widget.locked &&
          {
            LogicalKeyboardKey.select,
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.mediaPlayPause,
          }.contains(event.logicalKey)) {
        widget.controller.toggle();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _surface() => MouseRegion(
    cursor: visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
    onHover: (_) => _show(),
    child: Listener(
      onPointerDown: (_) {
        _keyboardInput = false;
        interacting = true;
        timer?.cancel();
      },
      onPointerUp: (_) {
        interacting = false;
        _arm();
      },
      onPointerCancel: (_) {
        interacting = false;
        _arm();
      },
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _gestureVideo(),
            if (shade > 0)
              IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: shade)),
              ),
            if (widget.controller.busy || widget.controller.state.buffering)
              const IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            if (widget.controller.error != null)
              Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.controller.error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: widget.locked
                              ? null
                              : widget.controller.retry,
                          child: const Text('重试'),
                        ),
                        if (widget.errorAction != null) widget.errorAction!,
                      ],
                    ),
                  ),
                ),
              ),
            if (hint != null)
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      hint!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            Positioned(top: 0, left: 0, right: 0, child: _chrome(_topBar())),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _chrome(_bottomBar()),
            ),
            if (visible)
              Positioned(
                right: 12,
                top: 60,
                child: IconButton.filledTonal(
                  tooltip: widget.locked ? '解除防误触' : '锁定防误触',
                  onPressed: () {
                    widget.onLock(!widget.locked);
                    _show();
                  },
                  icon: Icon(widget.locked ? Icons.lock : Icons.lock_open),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _chrome(Widget child) {
    final shown = visible && !widget.locked;
    return IgnorePointer(
      ignoring: !shown,
      child: ExcludeFocus(
        excluding: !shown,
        child: ExcludeSemantics(
          excluding: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: Focus(
              onFocusChange: (focused) {
                controlsFocused = focused;
                if (focused && _keyboardInput) {
                  timer?.cancel();
                } else {
                  _arm();
                }
              },
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black87, Colors.transparent],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              tooltip: '返回',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            IconButton(
              tooltip: '选集与播放设置',
              onPressed: widget.onOptions,
              icon: const Icon(Icons.tune, color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _bottomBar() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black87],
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: widget.transport,
      ),
    ),
  );

  Widget _gestureVideo() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _tap,
    onDoubleTap: widget.locked ? null : widget.controller.toggle,
    onLongPressStart: canGesture
        ? (_) {
            widget.controller.beginSpeed();
            setState(() => hint = '3× 倍速播放');
          }
        : null,
    onLongPressEnd: canGesture ? (_) => _endSpeed() : null,
    onLongPressCancel: _endSpeed,
    onHorizontalDragStart: canGesture && !widget.controller.isLive
        ? (_) {
            dragX = 0;
            seekStart = widget.controller.originalPosition;
            seekPreview = seekStart;
          }
        : null,
    onHorizontalDragUpdate: canGesture && !widget.controller.isLive
        ? (event) {
            dragX += event.delta.dx;
            final ms = (seekStart.inMilliseconds + dragX * 200).round().clamp(
              0,
              widget.controller.originalDuration.inMilliseconds,
            );
            setState(() {
              seekPreview = Duration(milliseconds: ms);
              hint = '跳转 ${clockText(seekPreview!)}';
            });
          }
        : null,
    onHorizontalDragEnd: canGesture
        ? (_) {
            if (seekPreview != null) widget.controller.seek(seekPreview!);
            setState(() {
              seekPreview = null;
              hint = null;
            });
          }
        : null,
    onHorizontalDragCancel: () => setState(() {
      seekPreview = null;
      hint = null;
    }),
    onVerticalDragStart: canGesture
        ? (event) {
            volumeSide = event.localPosition.dx > context.size!.width / 2;
            dragY = 0;
            baseVolume = widget.controller.state.volume;
            baseShade = shade;
          }
        : null,
    onVerticalDragUpdate: canGesture ? _vertical : null,
    onVerticalDragEnd: (_) => setState(() => hint = null),
    onVerticalDragCancel: () => setState(() => hint = null),
    child: widget.video,
  );

  void _vertical(DragUpdateDetails event) {
    dragY -= event.delta.dy / context.size!.height;
    if (volumeSide) {
      final volume = (baseVolume + dragY * 100).clamp(0.0, 100.0);
      widget.controller.engine.setVolume(volume);
      setState(() => hint = '音量 ${volume.round()}%');
    } else {
      setState(() {
        shade = (baseShade - dragY).clamp(0.0, .7);
        hint = '画面亮度 ${((1 - shade) * 100).round()}%';
      });
    }
  }

  void _endSpeed() {
    widget.controller.endSpeed();
    if (mounted) setState(() => hint = null);
  }
}
