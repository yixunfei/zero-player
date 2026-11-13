import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Touch devices can leave a book page from the leading edge, including when
/// the reader is hiding the Android system bars.
class BookPageRoute<T> extends MaterialPageRoute<T> {
  BookPageRoute({required super.builder});

  @override
  Widget buildContent(BuildContext context) {
    final content = super.buildContent(context);
    if (Theme.of(context).platform != TargetPlatform.android) return content;
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final leading = Directionality.of(context) == TextDirection.ltr
        ? insets.left
        : insets.right;
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: math.max(32, leading + 12),
          child: const _BookBackEdge(),
        ),
      ],
    );
  }
}

class _BookBackEdge extends StatefulWidget {
  const _BookBackEdge();

  @override
  State<_BookBackEdge> createState() => _BookBackEdgeState();
}

class _BookBackEdgeState extends State<_BookBackEdge> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    excludeFromSemantics: true,
    supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
    dragStartBehavior: DragStartBehavior.down,
    onHorizontalDragStart: (_) => _distance = 0,
    onHorizontalDragUpdate: (details) => _distance += details.primaryDelta ?? 0,
    onHorizontalDragEnd: (details) {
      final direction = Directionality.of(context) == TextDirection.ltr
          ? 1
          : -1;
      final distance = _distance * direction;
      final velocity = (details.primaryVelocity ?? 0) * direction;
      if (ModalRoute.of(context)?.isCurrent == true &&
          (distance >= 70 && velocity > -300 ||
              distance >= 28 && velocity > 500)) {
        unawaited(Navigator.maybePop(context));
      }
    },
  );
}
