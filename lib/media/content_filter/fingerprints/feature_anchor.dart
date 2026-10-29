import 'audio_fingerprint.dart';
import 'feature_sample_failure.dart';
import 'visual_fingerprint.dart';

/// A short observed signature, positioned inside the user's complete interval.
final class FeatureAnchor {
  const FeatureAnchor({
    required this.offsetMs,
    required this.durationMs,
    required this.visual,
    required this.audio,
  });
  final int offsetMs, durationMs;
  final List<VisualFingerprint> visual;
  final List<List<int>> audio;

  Map<String, Object> toJson() => {
    'offsetMs': offsetMs,
    'durationMs': durationMs,
    'visual': visual.map((frame) => frame.toJson()).toList(),
    'audio': audio,
  };

  factory FeatureAnchor.fromJson(Object? raw) {
    if (raw is! Map || raw['offsetMs'] is! int || raw['durationMs'] is! int) {
      throw const FormatException('特征锚点范围无效');
    }
    final pictures = raw['visual'], sound = raw['audio'];
    if (pictures is! List ||
        pictures.length > 24 ||
        sound is! List ||
        sound.length > 48) {
      throw const FormatException('特征锚点数据无效');
    }
    return FeatureAnchor(
      offsetMs: raw['offsetMs'] as int,
      durationMs: raw['durationMs'] as int,
      visual: pictures.map((v) {
        if (v is! Map) throw const FormatException('画面指纹无效');
        return VisualFingerprint.fromJson(v);
      }).toList(),
      audio: sound.map((v) {
        if (v is! List ||
            v.length != audioBands ||
            v.any((n) => n is! int || n < 0 || n > 255)) {
          throw const FormatException('音频指纹无效');
        }
        return v.cast<int>();
      }).toList(),
    );
  }

  void validate({required bool usesVisual, required bool usesAudio}) {
    if (offsetMs < 0 ||
        durationMs < 1000 ||
        durationMs > 12000 ||
        durationMs % 500 != 0 ||
        visual.length > 24 ||
        audio.length > 48) {
      throw const FormatException('特征锚点范围无效');
    }
    if (usesVisual && visual.length != durationMs ~/ 500) {
      throw FeatureSampleFailure(
        FeatureSampleIssue.incompleteVisual,
        '画面采集不完整（${visual.length}/${durationMs ~/ 500} 帧）。请重试或更换片段。',
      );
    }
    if (usesVisual && visual.where((v) => v.informative).length < 2) {
      throw const FeatureSampleFailure(
        FeatureSampleIssue.uninformativeVisual,
        '画面缺少清晰特征，请选择包含标识的片段，或仅保存本集区间。',
      );
    }
    if (usesAudio && audio.length != durationMs ~/ 250) {
      throw FeatureSampleFailure(
        FeatureSampleIssue.incompleteAudio,
        '音频采集不完整（${audio.length}/${durationMs ~/ 250} 帧）。请重试、改用画面或更换片段。',
      );
    }
    if (usesAudio && !informativeAudio(audio)) {
      throw const FeatureSampleFailure(
        FeatureSampleIssue.uninformativeAudio,
        '这段声音静音或变化不足，无法可靠识别。可改用画面，或仅保存本集区间。',
      );
    }
  }
}
