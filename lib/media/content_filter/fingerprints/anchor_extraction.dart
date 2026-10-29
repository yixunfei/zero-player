import 'dart:math';
import 'feature_anchor.dart';
import 'feature_rule.dart';
import 'feature_sample_failure.dart';
import 'sample_signature.dart';

/// Bounded sampling work, independent of the length of the marked interval.
List<(int, int)> anchorWindows(int lengthMs) {
  if (lengthMs <= 6000) return [(0, lengthMs)];
  final starts = <int>{0, 4000};
  if (lengthMs <= 48000) {
    for (var at = 8000; at + 1000 <= lengthMs; at += 4000) {
      starts.add(at);
    }
  } else {
    for (var i = 0; i < 10; i++) {
      starts.add(((8000 + (lengthMs - 12000) * i / 9) / 500).floor() * 500);
    }
  }
  return (starts.toList()..sort())
      .map((at) => (at, min(4000, lengthMs - at)))
      .toList();
}

FeatureAnchor observedAnchor(
  SampleSignature signature, {
  required int offsetMs,
  required int requestedMs,
  required FeatureMode mode,
}) {
  var observedMs = requestedMs;
  if (mode != FeatureMode.visual) {
    observedMs = min(observedMs, signature.audio.length * 250);
  }
  if (mode != FeatureMode.audio) {
    observedMs = min(observedMs, signature.visual.length * 500);
  }
  observedMs = observedMs ~/ 500 * 500;
  if (observedMs < 1000) {
    throw FeatureSampleFailure(
      mode == FeatureMode.visual
          ? FeatureSampleIssue.incompleteVisual
          : FeatureSampleIssue.incompleteAudio,
      '此处实际可采集内容不足 1 秒，请调整范围或改用另一种匹配方式。',
    );
  }
  final anchor = FeatureAnchor(
    offsetMs: offsetMs,
    durationMs: observedMs,
    visual: signature.visual.take(observedMs ~/ 500).toList(),
    audio: signature.audio.take(observedMs ~/ 250).toList(),
  );
  anchor.validate(
    usesVisual: mode != FeatureMode.audio,
    usesAudio: mode != FeatureMode.visual,
  );
  return anchor;
}
