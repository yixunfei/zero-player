import 'dart:isolate';
import '../../hls/timeline.dart';
import '../../../core/network/cancellation_token.dart';
import '../filter_types.dart';
import '../filter_strategy.dart';
import 'feature_matcher.dart';
import 'feature_rule.dart';
import 'sample_signature.dart';

final class FeatureInspector
    implements DeferredSliceInspector, TemporalSliceInspector {
  FeatureInspector(
    List<FeatureRule> rules, {
    this.enhancement,
    FilterStrategy strategy = FilterStrategy.conservative,
    this.denseSampling = false,
  }) : rules = List.unmodifiable(rules.where((r) => r.enabled)),
       matcher = FeatureMatcher(rules, strategy: strategy);
  final bool denseSampling;
  final List<FeatureRule> rules;
  FeatureMatcher matcher;
  final SliceInspector? enhancement;
  bool _enhancementReady = false;
  @override
  void reset() {
    matcher.reset();
    if (enhancement case final TemporalSliceInspector temporal) {
      temporal.reset();
    }
  }

  @override
  Duration get retention => rules.fold(
    Duration.zero,
    (duration, rule) => duration > rule.retention ? duration : rule.retention,
  );
  @override
  Future<void> prepare(CancellationToken token) async {
    token.check();
    if (rules.isEmpty && enhancement == null) {
      throw const FilterFailure('本渠道尚无启用的特征。请先关闭内容过滤并标注样本，或手动安装增强识别资源');
    }
    for (final rule in rules) {
      rule.validate();
    }
    try {
      await enhancement?.prepare(token);
      _enhancementReady = enhancement != null;
    } catch (_) {
      token.check();
      if (rules.isEmpty) rethrow;
      _enhancementReady = false;
    }
  }

  @override
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken token,
  ) async {
    token.check();
    final signature = rules.isEmpty
        ? null
        : await sampleSignature(
            slice,
            visual: rules.any((rule) => rule.usesVisual),
            audio: rules.any((rule) => rule.usesAudio),
            visualStepMs: denseSampling ? 250 : 500,
            audioStepMs: denseSampling ? 50 : 250,
          );
    token.check();
    var hits = <FeatureHit>[];
    if (signature != null) {
      final result = await _matchOffThread(
        matcher,
        signature,
        slice.start.inMilliseconds,
        (slice.start + slice.duration).inMilliseconds,
      );
      token.check();
      matcher = result.$1;
      hits = result.$2;
    }
    FilterDecision? extra;
    if (_enhancementReady) {
      try {
        // Enhanced OCR retains its 500 ms timestamp contract. Dense feature
        // frames must not double its inferred timestamps or inference work.
        final enhancedSlice = denseSampling
            ? MediaSlice(
                directory: slice.directory,
                media: slice.media,
                frames: slice.frames.indexed
                    .where((e) => e.$1.isEven)
                    .map((e) => e.$2)
                    .toList(),
                audio: slice.audio,
                start: slice.start,
                duration: slice.duration,
              )
            : slice;
        extra = await enhancement?.inspect(enhancedSlice, token);
      } catch (_) {
        token.check();
        if (rules.isEmpty) rethrow;
        extra = const FilterDecision(
          FilterVerdict.uncertain,
          reason: '增强检测暂不可用，仍应用用户特征',
        );
      }
    }
    token.check();
    if (hits.isEmpty && extra?.verdict == FilterVerdict.uncertain) {
      return extra!;
    }
    return _decision(hits, extra, slice);
  }

  FilterDecision _decision(
    List<FeatureHit> hits,
    FilterDecision? extra,
    MediaSlice slice,
  ) {
    final detections = hits
        .map((h) => FilterDetection(h.range, '命中内容特征：${h.rule.label}'))
        .toList();
    if (extra?.verdict == FilterVerdict.block) {
      final ranges = extra!.ranges.isEmpty
          ? [RemovedInterval(slice.start, slice.start + slice.duration)]
          : extra.ranges;
      detections.addAll(
        ranges.map(
          (range) => FilterDetection(
            range,
            '${extra.reason} · 需确认跳过',
            source: DetectionSource.keyword,
          ),
        ),
      );
    }
    if (detections.isEmpty) return const FilterDecision(FilterVerdict.allow);
    return FilterDecision(
      FilterVerdict.block,
      reason: hits.isEmpty
          ? extra!.reason
          : '命中内容特征：${hits.map((h) => h.rule.label).join('、')}',
      ranges: detections.map((hit) => hit.range).toList(),
      detections: detections,
    );
  }

  @override
  Future<void> close() async => enhancement?.close();
}

/// Copy bounded matcher state into the worker. Cancelled results never mutate
/// the live history, and dense matching does not block the Flutter UI isolate.
Future<(FeatureMatcher, List<FeatureHit>)> _matchOffThread(
  FeatureMatcher matcher,
  SampleSignature signature,
  int start,
  int end,
) => Isolate.run(() => (matcher, matcher.add(signature, start, end)));
