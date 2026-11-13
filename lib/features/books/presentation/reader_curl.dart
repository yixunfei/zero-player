import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ReaderCurl extends StatefulWidget {
  const ReaderCurl({
    super.key,
    required this.paper,
    required this.background,
    required this.animate,
    required this.page,
    required this.canTurn,
    required this.onTurn,
    required this.pageBuilder,
  });

  final Color paper;
  final Widget background;
  final bool animate;
  final int page;
  final bool Function(int direction) canTurn;
  final ValueChanged<int> onTurn;
  final Widget Function(int page, bool selectable) pageBuilder;

  @override
  State<ReaderCurl> createState() => ReaderCurlState();
}

class ReaderCurlState extends State<ReaderCurl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fold = AnimationController(vsync: this);
  int _direction = 0;
  double _delta = 0, _pull = .5;
  bool _settling = false;

  void turn(int direction) {
    if (_settling || _direction != 0 || !widget.canTurn(direction)) return;
    setState(() {
      _direction = direction;
      _pull = .62;
    });
    _settle(true);
  }

  void _drag(DragUpdateDetails event, Size size) {
    if (_settling) return;
    _delta += event.primaryDelta ?? 0;
    _pull = (event.localPosition.dy / size.height).clamp(0.0, 1.0);
    if (_direction == 0) {
      final direction = _delta < 0 ? 1 : -1;
      if (!widget.canTurn(direction)) return;
      setState(() => _direction = direction);
    }
    _fold.value = (-_delta * _direction / size.width).clamp(0.0, 1.0);
  }

  void _release(DragEndDetails event) {
    if (_direction == 0 || _settling) return;
    final velocity = -(event.primaryVelocity ?? 0) * _direction;
    _settle(velocity > 480 || (_fold.value >= .26 && velocity > -480));
  }

  Future<void> _settle(bool commit) async {
    _settling = true;
    final direction = _direction;
    try {
      if (widget.animate) {
        final target = commit ? 1.0 : 0.0;
        await _fold
            .animateTo(
              target,
              duration: Duration(
                milliseconds: (155 + (target - _fold.value).abs() * 170)
                    .round(),
              ),
              curve: Curves.easeOutCubic,
            )
            .orCancel;
      }
      if (!mounted) return;
      setState(() {
        _direction = 0;
        _delta = 0;
        _settling = false;
        _fold.value = 0;
      });
      if (commit) widget.onTurn(direction);
    } on TickerCanceled {
      // The viewport was replaced during the animation.
    }
  }

  @override
  void dispose() {
    _fold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      },
      onHorizontalDragStart: (event) {
        if (_settling) return;
        _delta = 0;
        _pull = (event.localPosition.dy / constraints.maxHeight).clamp(
          0.0,
          1.0,
        );
      },
      onHorizontalDragUpdate: (event) => _drag(event, constraints.biggest),
      onHorizontalDragEnd: _release,
      onHorizontalDragCancel: () {
        if (_direction != 0 && !_settling) _settle(false);
      },
      child: AnimatedBuilder(
        animation: _fold,
        child: widget.pageBuilder(widget.page, true),
        builder: (context, page) {
          if (_direction == 0) return page!;
          final fold = _PageFold(_fold.value, _pull, _direction < 0);
          return Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: widget.pageBuilder(widget.page + _direction, false),
              ),
              ClipPath(
                clipper: fold,
                child: Stack(
                  fit: StackFit.expand,
                  children: [widget.background, page!],
                ),
              ),
              IgnorePointer(
                child: CustomPaint(painter: _FoldShade(fold, widget.paper)),
              ),
            ],
          );
        },
      ),
    ),
  );
}

final class _PageFold extends CustomClipper<Path> {
  const _PageFold(this.progress, this.pull, this.mirror);
  final double progress, pull;
  final bool mirror;

  (double, double, double) crease(Size size) {
    final sweep = math.sin(progress * math.pi);
    final angle = (pull - .5) * sweep * size.width * .28;
    final x = size.width * (1 - progress);
    return (x + angle, x - angle, size.width * sweep * .15);
  }

  double x(double value, Size size) => mirror ? size.width - value : value;

  @override
  Path getClip(Size size) {
    final (top, bottom, width) = crease(size);
    return Path()
      ..moveTo(x(0, size), 0)
      ..lineTo(x(top, size), 0)
      ..quadraticBezierTo(
        x((top + bottom) / 2 - width * .5, size),
        size.height * pull,
        x(bottom, size),
        size.height,
      )
      ..lineTo(x(0, size), size.height)
      ..close();
  }

  @override
  bool shouldReclip(_PageFold oldClipper) =>
      oldClipper.progress != progress ||
      oldClipper.pull != pull ||
      oldClipper.mirror != mirror;
}

final class _FoldShade extends CustomPainter {
  const _FoldShade(this.fold, this.paper);
  final _PageFold fold;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final (top, bottom, width) = fold.crease(size);
    if (width <= .1) return;
    double x(double value) => fold.x(value, size);
    final edge = (top + bottom) / 2;
    final shadow = Path()
      ..moveTo(x(top), 0)
      ..lineTo(x(top + width * 1.9), 0)
      ..lineTo(x(bottom + width * 1.9), size.height)
      ..lineTo(x(bottom), size.height)
      ..close();
    canvas.drawPath(
      shadow,
      Paint()
        ..shader =
            LinearGradient(
              colors: [Colors.black.withValues(alpha: .32), Colors.transparent],
              begin: fold.mirror ? Alignment.centerRight : Alignment.centerLeft,
              end: fold.mirror ? Alignment.centerLeft : Alignment.centerRight,
            ).createShader(
              Rect.fromLTRB(
                math.min(x(edge), x(edge + width * 1.9)),
                0,
                math.max(x(edge), x(edge + width * 1.9)),
                size.height,
              ),
            ),
    );
    final back = Path()
      ..moveTo(x(top), 0)
      ..lineTo(x(top + width * .72), 0)
      ..quadraticBezierTo(
        x(edge + width * 1.18),
        size.height * .56,
        x(bottom + width * .63),
        size.height,
      )
      ..lineTo(x(bottom), size.height)
      ..close();
    canvas.drawPath(
      back,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.alphaBlend(Colors.black26, paper),
            paper,
            Color.alphaBlend(Colors.white24, paper),
          ],
          stops: const [0, .55, 1],
          begin: fold.mirror ? Alignment.centerRight : Alignment.centerLeft,
          end: fold.mirror ? Alignment.centerLeft : Alignment.centerRight,
        ).createShader(back.getBounds()),
    );
  }

  @override
  bool shouldRepaint(_FoldShade oldDelegate) =>
      oldDelegate.paper != paper || fold.shouldReclip(oldDelegate.fold);
}
