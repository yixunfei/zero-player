import 'dart:convert';
import 'package:image/image.dart' as img;
import 'audio_fingerprint.dart';
import 'feature_anchor.dart';
import 'visual_fingerprint.dart';

enum FeatureMode { visual, audio, both }

enum FeatureScope { channel, series }

final class FeatureRule {
  FeatureRule({
    required this.id,
    required this.sourceId,
    required this.label,
    required this.mode,
    required this.sampleMs,
    required this.beforeMs,
    required this.afterMs,
    required this.visual,
    required this.audio,
    required this.thumbnail,
    required this.originKey,
    required this.originStartMs,
    this.anchors = const [],
    this.captureNote = '',
    this.enabled = true,
    this.scope = FeatureScope.channel,
    this.seriesKey = '',
  });
  final String id, sourceId, label, thumbnail, originKey;
  final FeatureMode mode;
  final int sampleMs, beforeMs, afterMs, originStartMs;
  final List<VisualFingerprint> visual;
  final List<List<int>> audio;
  final List<FeatureAnchor> anchors;
  final String captureNote;
  List<FeatureAnchor> get signatures => anchors.isNotEmpty
      ? anchors
      : [
          FeatureAnchor(
            offsetMs: 0,
            durationMs: sampleMs,
            visual: visual,
            audio: audio,
          ),
        ];
  int get longestAnchorMs =>
      signatures.fold(0, (n, a) => n > a.durationMs ? n : a.durationMs);

  /// Recover enough nearby evidence for two anchors after a seek/resume.
  int get reacquireMs {
    final ordered = signatures.toList()
      ..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
    if (ordered.length < 2) return sampleMs + afterMs;
    var window = longestAnchorMs * 2;
    for (var i = 2; i < ordered.length; i++) {
      final span =
          ordered[i].offsetMs + ordered[i].durationMs - ordered[i - 2].offsetMs;
      if (span > window) window = span;
    }
    final tail = sampleMs + afterMs - ordered[ordered.length - 2].offsetMs;
    if (tail > window) window = tail;
    return window.clamp(0, sampleMs + afterMs);
  }

  final bool enabled;
  final FeatureScope scope;
  final String seriesKey;
  bool appliesTo({required String source, required String series}) =>
      scope == FeatureScope.channel ? sourceId == source : seriesKey == series;

  FeatureRule copyWith({
    String? id,
    String? label,
    FeatureScope? scope,
    String? seriesKey,
    bool? enabled,
    int? beforeMs,
    int? afterMs,
  }) => FeatureRule.fromJson({
    ...toJson(),
    'id': id ?? this.id,
    'label': label ?? this.label,
    'scope': (scope ?? this.scope).name,
    'seriesKey': seriesKey ?? this.seriesKey,
    'enabled': enabled ?? this.enabled,
    'beforeMs': beforeMs ?? this.beforeMs,
    'afterMs': afterMs ?? this.afterMs,
  });
  bool get usesVisual => mode != FeatureMode.audio;
  bool get usesAudio => mode != FeatureMode.visual;
  Duration get retention => Duration(milliseconds: sampleMs + beforeMs + 4000);

  Map<String, Object> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'label': label,
    'mode': mode.name,
    'sampleMs': sampleMs,
    'anchors': anchors.map((anchor) => anchor.toJson()).toList(),
    'captureNote': captureNote,
    'beforeMs': beforeMs,
    'afterMs': afterMs,
    'visual': visual.map((f) => f.toJson()).toList(),
    'audio': audio,
    'thumbnail': thumbnail,
    'originKey': originKey,
    'originStartMs': originStartMs,
    'enabled': enabled,
    'scope': scope.name,
    'seriesKey': seriesKey,
  };

  factory FeatureRule.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('特征规则无效');
    String string(String key, int max) {
      final value = raw[key];
      if (value is! String || value.length > max) {
        throw const FormatException('特征文字无效');
      }
      return value;
    }

    int integer(String key, int low, int high) {
      final value = raw[key];
      if (value is! int || value < low || value > high) {
        throw const FormatException('特征范围无效');
      }
      return value;
    }

    final mode = FeatureMode.values
        .where((v) => v.name == raw['mode'])
        .firstOrNull;
    final scope = FeatureScope.values
        .where((v) => v.name == (raw['scope'] ?? 'channel'))
        .firstOrNull;
    final pictures = raw['visual'], sound = raw['audio'];
    if (mode == null ||
        scope == null ||
        pictures is! List ||
        pictures.length > 24 ||
        sound is! List ||
        sound.length > 48 ||
        raw['enabled'] is! bool) {
      throw const FormatException('特征参数无效');
    }
    final visual = pictures.map((v) {
      if (v is! Map) throw const FormatException('画面指纹无效');
      return VisualFingerprint.fromJson(v);
    }).toList();
    final audio = sound.map((v) {
      if (v is! List ||
          v.length != audioBands ||
          v.any((n) => n is! int || n < 0 || n > 255)) {
        throw const FormatException('音频指纹无效');
      }
      return v.cast<int>();
    }).toList();
    final rawAnchors = raw['anchors'] ?? [];
    if (rawAnchors is! List || rawAnchors.length > 12) {
      throw const FormatException('特征锚点过多');
    }
    final rule = FeatureRule(
      anchors: rawAnchors.map(FeatureAnchor.fromJson).toList(),
      captureNote: raw.containsKey('captureNote')
          ? string('captureNote', 1000)
          : '',
      id: string('id', 128),
      sourceId: string('sourceId', 128),
      label: string('label', 120),
      mode: mode,
      sampleMs: integer('sampleMs', 1000, 600000),
      beforeMs: integer('beforeMs', 0, 30000),
      afterMs: integer('afterMs', 0, 120000),
      originStartMs: integer('originStartMs', 0, 86400000),
      originKey: string('originKey', 2048),
      thumbnail: string('thumbnail', 60000),
      enabled: raw['enabled'] as bool,
      scope: scope,
      seriesKey: raw.containsKey('seriesKey') ? string('seriesKey', 2048) : '',
      visual: visual,
      audio: audio,
    );
    rule.validate();
    return rule;
  }

  void validate() {
    if (seriesKey.length > 2048 ||
        (scope == FeatureScope.series && seriesKey.trim().isEmpty) ||
        id.length > 128 ||
        sourceId.length > 128 ||
        label.length > 120 ||
        originKey.length > 2048 ||
        originStartMs < 0 ||
        originStartMs > 86400000 ||
        anchors.length > 12 ||
        captureNote.length > 1000 ||
        visual.length > 24 ||
        audio.length > 48 ||
        id.isEmpty ||
        sourceId.isEmpty ||
        label.trim().isEmpty ||
        sampleMs < 1000 ||
        sampleMs > 600000 ||
        beforeMs < 0 ||
        beforeMs > 30000 ||
        afterMs < 0 ||
        afterMs > 120000) {
      throw const FormatException('特征范围或名称无效');
    }
    var previousEnd = 0;
    for (final anchor in signatures) {
      if (anchor.offsetMs < previousEnd ||
          anchor.offsetMs + anchor.durationMs > sampleMs) {
        throw const FormatException('特征锚点超出标记片段');
      }
      anchor.validate(usesVisual: usesVisual, usesAudio: usesAudio);
      previousEnd = anchor.offsetMs + anchor.durationMs;
    }
    if (sampleMs > 12000 && signatures.length < 2) {
      throw const FormatException('长片段需要至少两个有效短特征，请调整范围或改用画面');
    }
    final preview = base64Decode(thumbnail);
    if (preview.length > 45000) {
      throw const FormatException('预览图过大');
    }
    if (preview.isNotEmpty) {
      final info = img.JpegDecoder().startDecode(preview);
      if (info == null ||
          info.width > 240 ||
          info.height > 480 ||
          info.width < 1 ||
          info.height < 1) {
        throw const FormatException('预览图格式或尺寸无效');
      }
    }
  }
}
