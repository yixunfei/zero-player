import 'dart:typed_data';

/// Bounded audio preceding the current slice, without duplicating its overlap.
final class KeywordAudioContext {
  Float32List _tail = Float32List(0);
  int? _previousStartMs, _previousEndMs;

  void reset() {
    _tail = Float32List(0);
    _previousStartMs = _previousEndMs = null;
  }

  ({Float32List samples, int prefixMs, bool continuous}) append(
    Float32List samples,
    int? startMs,
  ) {
    final overlap = (_previousEndMs ?? 0) - (startMs ?? 0);
    final continuous =
        startMs != null &&
        _previousStartMs != null &&
        startMs > _previousStartMs! &&
        overlap >= -60 &&
        overlap * 16 <= _tail.length;
    final count = continuous
        ? (_tail.length - overlap * 16).clamp(0, _tail.length)
        : 0;
    final combined = Float32List(count + samples.length)
      ..setRange(0, count, _tail)
      ..setAll(count, samples);
    _tail = Float32List.fromList(
      combined.sublist((combined.length - 24000).clamp(0, combined.length)),
    );
    _previousStartMs = startMs;
    _previousEndMs = startMs == null ? null : startMs + samples.length ~/ 16;
    return (samples: combined, prefixMs: count ~/ 16, continuous: continuous);
  }
}
