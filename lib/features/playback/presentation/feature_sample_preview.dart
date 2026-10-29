import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../media/content_filter/fingerprints/feature_rule.dart';
import '../domain/feature_time.dart';

/// Displays stored evidence, without reopening a stream or installing models.
final class FeatureSamplePreview extends StatelessWidget {
  const FeatureSamplePreview({super.key, required this.rule});
  final FeatureRule rule;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (rule.thumbnail.isNotEmpty)
        Image.memory(
          base64Decode(rule.thumbnail),
          height: 135,
          fit: BoxFit.contain,
          semanticLabel: '采集的特征画面',
        ),
      if (rule.usesAudio) ...[
        const Text('首个短特征音频预览 · 横向为时间，纵向为频段'),
        const SizedBox(height: 6),
        Semantics(
          label: '音频频谱序列，${rule.audio.length} 帧',
          child: SizedBox(
            height: 64,
            width: double.infinity,
            child: CustomPaint(
              painter: _SpectrumPainter(
                rule.audio,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        Text(
          '有效声音 ${rule.audio.where((f) => f.any((v) => v > 0)).length}'
          ' / ${rule.audio.length} 帧；静音仅作时间结构，不作为命中证据。',
        ),
      ],
      if (rule.usesVisual)
        Text(
          '清晰画面 ${rule.visual.where((f) => f.informative).length}'
          ' / ${rule.visual.length} 帧',
        ),
      Text(
        '完整片段 ${(rule.sampleMs / 1000).toStringAsFixed(3)} 秒 · ${rule.signatures.length} 个短特征',
      ),
      for (final (index, anchor) in rule.signatures.indexed)
        Text(
          '短特征 ${index + 1}：片段内 +${featureTimeText(anchor.offsetMs)}，'
          '持续 ${anchor.durationMs / 1000} 秒；'
          '${anchor.visual.length} 画面 / ${anchor.audio.length} 音频帧',
        ),
    ],
  );
}

final class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter(this.frames, this.color);
  final List<List<int>> frames;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;
    final paint = Paint();
    final width = size.width / frames.length;
    for (var x = 0; x < frames.length; x++) {
      final bands = frames[x];
      final height = size.height / bands.length;
      for (var y = 0; y < bands.length; y++) {
        paint.color = color.withValues(alpha: .08 + bands[y] / 255 * .92);
        canvas.drawRect(
          Rect.fromLTWH(
            x * width,
            size.height - (y + 1) * height,
            width,
            height,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      oldDelegate.frames != frames || oldDelegate.color != color;
}
