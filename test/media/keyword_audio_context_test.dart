import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/content_filter/keyword_audio_context.dart';

void main() {
  test('overlapping feature probes preserve preceding audio exactly once', () {
    final context = KeywordAudioContext();
    Float32List audio(int start, int length) => Float32List.fromList(
      List.generate(length, (i) => (start + i).toDouble()),
    );
    context.append(audio(0, 72000), 0);
    final next = context.append(audio(64000, 72000), 4000);
    expect(next.continuous, isTrue);
    expect(next.prefixMs, 1000);
    expect(next.samples, audio(48000, 88000));
    final adjacent = context.append(audio(136000, 16000), 8500);
    expect(adjacent.prefixMs, 1500);
    expect(adjacent.samples, audio(112000, 40000));
  });
  test('seek, retry and explicit reset cannot retain stale audio context', () {
    final context = KeywordAudioContext();
    context.append(Float32List(64000), 0);
    expect(context.append(Float32List(64000), 0).continuous, isFalse);
    context.reset();
    expect(context.append(Float32List(64000), 4000).prefixMs, 0);
    expect(context.append(Float32List(64000), 20000).continuous, isFalse);
  });
}
