import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../data/skip_repository.dart';

final class TimelineSlider extends StatefulWidget {
  const TimelineSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.marks,
    required this.seek,
    this.buffer = Duration.zero,
  });
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final List<SkipMark> marks;
  final ValueChanged<Duration> seek;
  @override
  State<TimelineSlider> createState() => _TimelineSliderState();
}

final class _TimelineSliderState extends State<TimelineSlider> {
  double? preview;
  double? hover;

  void _hover(PointerEvent event, double width) {
    if (widget.duration <= Duration.zero) return;
    setState(() {
      hover =
          ((event.localPosition.dx - 24) /
                  (width - 48).clamp(1, double.maxFinite))
              .clamp(0.0, 1.0) *
          widget.duration.inMilliseconds;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 2,
        children: [
          Text(
            '${clockText(Duration(milliseconds: (preview ?? widget.position.inMilliseconds).round()))} / ${clockText(widget.duration)}',
            key: const ValueKey('playback-time'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          Text(
            hover != null && preview == null
                ? '跳转 ${clockText(Duration(milliseconds: hover!.round()))}'
                : '缓冲 ${clockText(widget.buffer > widget.duration ? widget.duration : widget.buffer)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
      LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          onHover: (event) => _hover(event, constraints.maxWidth),
          onExit: (_) => setState(() => hover = null),
          child: _slider(context),
        ),
      ),
    ],
  );

  Widget _slider(BuildContext context) => CustomPaint(
    painter: _MarksPainter(
      widget.marks,
      widget.duration,
      Theme.of(context).colorScheme.tertiary,
    ),
    child: SliderTheme(
      data: SliderTheme.of(
        context,
      ).copyWith(showValueIndicator: ShowValueIndicator.onDrag),
      child: Slider(
        label: clockText(
          Duration(
            milliseconds: (preview ?? widget.position.inMilliseconds).round(),
          ),
        ),
        semanticFormatterCallback: (value) =>
            '播放时间 ${clockText(Duration(milliseconds: value.round()))}',
        secondaryTrackValue: widget.buffer.inMilliseconds.toDouble().clamp(
          (preview ?? widget.position.inMilliseconds.toDouble()).clamp(
            0,
            widget.duration.inMilliseconds.toDouble(),
          ),
          widget.duration.inMilliseconds.toDouble().clamp(1, double.maxFinite),
        ),
        value: (preview ?? widget.position.inMilliseconds.toDouble()).clamp(
          0,
          widget.duration.inMilliseconds.toDouble(),
        ),
        max: widget.duration.inMilliseconds.toDouble().clamp(
          1,
          double.maxFinite,
        ),
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
