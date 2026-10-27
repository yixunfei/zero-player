import 'package:flutter/material.dart';
import '../data/skip_repository.dart';

final class TimelineSlider extends StatefulWidget {
  const TimelineSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.marks,
    required this.seek,
  });
  final Duration position;
  final Duration duration;
  final List<SkipMark> marks;
  final ValueChanged<Duration> seek;
  @override
  State<TimelineSlider> createState() => _TimelineSliderState();
}

final class _TimelineSliderState extends State<TimelineSlider> {
  double? preview;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MarksPainter(
      widget.marks,
      widget.duration,
      Theme.of(context).colorScheme.tertiary,
    ),
    child: Slider(
      value: (preview ?? widget.position.inMilliseconds.toDouble()).clamp(
        0,
        widget.duration.inMilliseconds.toDouble(),
      ),
      max: widget.duration.inMilliseconds.toDouble().clamp(1, double.maxFinite),
      onChanged: widget.duration == Duration.zero
          ? null
          : (value) => setState(() => preview = value),
      onChangeEnd: widget.duration == Duration.zero
          ? null
          : (value) {
              widget.seek(Duration(milliseconds: value.round()));
              setState(() => preview = null);
            },
    ),
  );
}

final class _MarksPainter extends CustomPainter {
  _MarksPainter(this.marks, this.duration, this.color);
  final List<SkipMark> marks;
  final Duration duration;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (duration <= Duration.zero) return;
    final paint = Paint()..color = color;
    for (final mark in marks.where((m) => m.enabled)) {
      final left =
          24 +
          (size.width - 48) *
              (mark.start.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
      final right =
          24 +
          (size.width - 48) *
              (mark.end.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
      canvas.drawRect(
        Rect.fromLTRB(left, size.height - 8, right, size.height - 4),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarksPainter oldDelegate) =>
      oldDelegate.marks != marks ||
      oldDelegate.duration != duration ||
      oldDelegate.color != color;
}
