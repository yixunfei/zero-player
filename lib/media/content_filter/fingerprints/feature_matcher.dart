import '../../hls/timeline.dart';
import '../filter_strategy.dart';
import 'audio_fingerprint.dart';
import 'feature_anchor.dart';
import 'feature_rule.dart';
import 'sample_signature.dart';
import 'visual_fingerprint.dart';

final class FeatureHit {
  const FeatureHit(this.rule, this.startMs, {this.scale = 1});
  final FeatureRule rule;
  final int startMs;
  final double scale;
  RemovedInterval get range => RemovedInterval(
    Duration(milliseconds: (startMs - rule.beforeMs).clamp(0, 86400000)),
    Duration(
      milliseconds: startMs + (rule.sampleMs * scale).round() + rule.afterMs,
    ),
  );
}

final class _Timed<T> {
  const _Timed(this.ms, this.value);
  final int ms;
  final T value;
}

/// Ordered local signatures. Origin timestamps never constrain candidates.
/// Overlapping probes retain evidence across boundaries; seeks clear it.
final class FeatureMatcher {
  FeatureMatcher(
    List<FeatureRule> rules, {
    this.strategy = FilterStrategy.conservative,
  }) : rules = rules.where((r) => r.enabled).toList();
  final List<FeatureRule> rules;
  final FilterStrategy strategy;
  final _pictures = <_Timed<VisualFingerprint>>[];
  final _sound = <_Timed<List<int>>>[];
  final _suppressUntil = <String, int>{};
  final _evidence = <String, List<(int, int, double)>>{};
  int? _lastEnd, _lastStart;
  bool get _aggressive => strategy == FilterStrategy.aggressive;

  List<FeatureHit> add(SampleSignature signature, int startMs, int endMs) {
    if (_lastEnd != null &&
        (startMs < _lastStart! || startMs > _lastEnd! + 50)) {
      reset();
    }
    final previous = _lastEnd ?? startMs;
    _pictures.removeWhere((p) => p.ms >= startMs);
    _sound.removeWhere((p) => p.ms >= startMs);
    _pictures.addAll(
      signature.visual.indexed.map(
        (e) => _Timed(startMs + e.$1 * signature.visualStepMs, e.$2),
      ),
    );
    _sound.addAll(
      signature.audio.indexed.map(
        (e) => _Timed(startMs + e.$1 * signature.audioStepMs, e.$2),
      ),
    );
    final hits = <FeatureHit>[];
    for (final rule in rules) {
      hits.addAll(_findHits(rule, previous, endMs));
    }
    _lastStart = startMs;
    _lastEnd = endMs;
    _pictures.removeWhere((p) => p.ms < endMs - 14000);
    _sound.removeWhere((p) => p.ms < endMs - 14000);
    return hits;
  }

  List<FeatureHit> _findHits(FeatureRule rule, int previous, int endMs) {
    final hits = <FeatureHit>[];
    final anchors = rule.signatures;
    final evidence = _evidence.putIfAbsent(rule.id, () => []);
    evidence.removeWhere((v) => v.$2 + rule.sampleMs < endMs - 14000);
    for (final (index, anchor) in anchors.indexed) {
      final candidates = rule.usesAudio
          ? _sound.map((p) => p.ms)
          : _pictures.map((p) => p.ms);
      for (final candidate in candidates) {
        final scale = _match(rule, anchor, candidate, previous, endMs);
        if (scale == null) continue;
        final start = candidate - (anchor.offsetMs * scale).round();
        if (start < -150 || start < (_suppressUntil[rule.id] ?? -1)) continue;
        if (!evidence.any((v) => v.$1 == index && (v.$2 - start).abs() < 150)) {
          evidence.add((index, start, scale));
        }
      }
    }
    // Evaluate every anchor before choosing a boundary. Repeated audio may
    // match an early anchor again later; iteration order is not evidence.
    final ordered = evidence.toList()..sort((a, b) => a.$2.compareTo(b.$2));
    for (final candidate in ordered) {
      final start = candidate.$2, scale = candidate.$3;
      if (start < (_suppressUntil[rule.id] ?? -1)) continue;
      final agreeing = evidence.where(
        (v) => (v.$2 - start).abs() <= 150 && (v.$3 - scale).abs() < .01,
      );
      if (anchors.length > 1 && agreeing.map((v) => v.$1).toSet().length < 2) {
        continue;
      }
      final hit = FeatureHit(rule, start.clamp(0, 86400000), scale: scale);
      hits.add(hit);
      _suppressUntil[rule.id] = hit.range.end.inMilliseconds;
    }
    if (hits.isNotEmpty) {
      evidence.removeWhere((v) => v.$2 < _suppressUntil[rule.id]!);
    }
    return hits;
  }

  void reset() {
    _pictures.clear();
    _sound.clear();
    _suppressUntil.clear();
    _evidence.clear();
    _lastStart = null;
    _lastEnd = null;
  }

  double? _match(
    FeatureRule rule,
    FeatureAnchor anchor,
    int start,
    int previous,
    int end,
  ) {
    final scales = _aggressive ? const [1.0, .96, 1.04] : const [1.0];
    for (final scale in scales) {
      final finish = start + (anchor.durationMs * scale).round();
      if (finish > end + 40 || finish <= previous) continue;
      if (rule.usesVisual && !_matchesVisual(anchor, start, scale)) continue;
      if (rule.usesAudio && !_matchesAudio(anchor, start, scale)) continue;
      return scale;
    }
    return null;
  }

  bool _matchesVisual(FeatureAnchor rule, int start, double scale) {
    var total = 0.0, strong = 0, compared = 0;
    for (var i = 0; i < rule.visual.length; i++) {
      final actual = _nearest(
        _pictures,
        start + (i * 500 * scale).round(),
        135,
      );
      if (actual == null) return false;
      final expected = rule.visual[i];
      if (!expected.informative) {
        if (actual.informative) return false;
        continue;
      }
      if (!actual.informative) return false;
      compared++;
      final score = expected.similarity(actual);
      total += score;
      if (score >= (_aggressive ? .86 : .90)) strong++;
    }
    return compared >= 2 &&
        total / compared >= (_aggressive ? .89 : .92) &&
        strong / compared >= (_aggressive ? .75 : .85);
  }

  bool _matchesAudio(FeatureAnchor rule, int start, double scale) {
    var total = 0.0, strong = 0, compared = 0;
    for (var i = 0; i < rule.audio.length; i++) {
      final actual = _nearest(
        _sound,
        start + (i * audioStepMs * scale).round(),
        65,
      );
      if (actual == null) return false;
      if (rule.audio[i].every((v) => v == 0)) {
        // Preserve pause structure; silence alone is never positive evidence.
        if (actual.any((v) => v != 0)) return false;
        continue;
      }
      compared++;
      final score = audioSimilarity(rule.audio[i], actual);
      total += score;
      if (score >= (_aggressive ? .86 : .90)) strong++;
    }
    return compared >= 4 &&
        total / compared >= (_aggressive ? .90 : .94) &&
        strong / compared >= (_aggressive ? .75 : .85);
  }
}

T? _nearest<T>(List<_Timed<T>> values, int target, int tolerance) {
  var low = 0, high = values.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (values[middle].ms < target) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  _Timed<T>? best;
  if (low < values.length) best = values[low];
  if (low > 0 &&
      (best == null ||
          (values[low - 1].ms - target).abs() < (best.ms - target).abs())) {
    best = values[low - 1];
  }
  return best != null && (best.ms - target).abs() <= tolerance
      ? best.value
      : null;
}
