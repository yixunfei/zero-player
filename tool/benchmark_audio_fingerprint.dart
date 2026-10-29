import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:zero_player/media/content_filter/fingerprints/audio_fingerprint.dart';

/// Deterministic workload; compare digests and timings on the same runtime.
void main(List<String> arguments) {
  final stepMs = arguments.isEmpty ? 250 : int.parse(arguments.first);
  final pcm = Float64List.fromList(
    List.generate(64000, (i) {
      final t = i / 16000;
      final envelope = .25 + .2 * math.sin(2 * math.pi * 3 * t);
      return envelope *
          (math.sin(2 * math.pi * 220 * t) +
              .4 * math.sin(2 * math.pi * (660 + 20 * t) * t));
    }),
  );
  for (var i = 0; i < 5; i++) {
    audioFingerprint(pcm, stepMs: stepMs);
  }
  const iterations = 30;
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    audioFingerprint(pcm, stepMs: stepMs);
  }
  watch.stop();
  final signature = audioFingerprint(pcm, stepMs: stepMs);
  stdout.writeln(
    jsonEncode({
      'sampleSeconds': 4,
      'stepMs': stepMs,
      'iterations': iterations,
      'meanMs': watch.elapsedMicroseconds / iterations / 1000,
      'frames': signature.length,
      'sha256': sha256.convert(utf8.encode(jsonEncode(signature))).toString(),
      'runtime': Platform.version,
    }),
  );
}
