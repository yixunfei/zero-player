import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:zero_player/media/content_filter/keyword_detector.dart';

Future<void> main(List<String> args) async {
  final runtime = Directory('.tools/content-filter/runtime').absolute.path;
  final model = Directory(
    '.tools/content-filter/kws-source/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20',
  ).absolute.path;
  DynamicLibrary.open('$runtime/onnxruntime.dll');
  sherpa.initBindings(runtime);
  final detector = KeywordDetector(model, runtime);
  try {
    for (final file
        in args.isEmpty
            ? ['test_support/generated/content_filter/speech.wav']
            : args) {
      final watch = Stopwatch()..start();
      final result = detector.inspect(File(file).absolute.path);
      stdout.writeln(
        '$file: ${result?.word} at ${result?.offset.inMilliseconds}ms in ${watch.elapsedMilliseconds}ms',
      );
      if (result == null) exitCode = 1;
    }
  } finally {
    detector.close();
  }
  if (args.isEmpty) {
    await _checkBoundary(model, runtime);
    await _checkOverlap(model, runtime);
  }
}

Future<void> _checkBoundary(String model, String runtime) async {
  final wave = sherpa.readWave(
    File('test_support/generated/content_filter/speech.wav').absolute.path,
  );
  final directory = await Directory.systemTemp.createTemp('keyword-boundary-');
  final detector = KeywordDetector(model, runtime);
  const split = 20800; // 1.3s falls inside the spoken keyword 澳门.
  try {
    final first = '${directory.path}/first.wav',
        second = '${directory.path}/second.wav';
    sherpa.writeWave(
      filename: first,
      samples: Float32List.fromList(wave.samples.take(split).toList()),
      sampleRate: 16000,
    );
    sherpa.writeWave(
      filename: second,
      samples: Float32List.fromList(wave.samples.skip(split).toList()),
      sampleRate: 16000,
    );
    final before = detector.inspect(first, startMs: 0);
    final after = detector.inspect(second, startMs: 1300);
    final hit = before ?? after;
    if (hit == null || hit.word != '澳门') {
      throw StateError('Cross-boundary keyword lost');
    }
    final at = before != null
        ? before.offset.inMilliseconds
        : 1300 + after!.offset.inMilliseconds;
    if (at < 900 || at > 1500) {
      throw StateError('Wrong cross-boundary origin: $at');
    }
    stdout.writeln('Cross-boundary keyword: ${hit.word} at ${at}ms');
  } finally {
    detector.close();
    await directory.delete(recursive: true);
  }
}

Future<void> _checkOverlap(String model, String runtime) async {
  final wave = sherpa.readWave(
    File('test_support/generated/content_filter/speech.wav').absolute.path,
  );
  final directory = await Directory.systemTemp.createTemp('keyword-overlap-');
  final detector = KeywordDetector(model, runtime);
  try {
    final first = '${directory.path}/first.wav';
    final second = '${directory.path}/second.wav';
    const firstEnd = 28800, secondStart = 20800;
    sherpa.writeWave(
      filename: first,
      samples: Float32List.fromList(wave.samples.take(firstEnd).toList()),
      sampleRate: 16000,
    );
    sherpa.writeWave(
      filename: second,
      samples: Float32List.fromList(wave.samples.skip(secondStart).toList()),
      sampleRate: 16000,
    );
    final before = detector.inspect(first, startMs: 0);
    final after = detector.inspect(second, startMs: 1300);
    final hit = before ?? after;
    final at =
        before?.offset.inMilliseconds ??
        (after == null ? -1 : 1300 + after.offset.inMilliseconds);
    if (hit?.word != '澳门' || at < 900 || at > 1500) {
      throw StateError('Overlapping keyword context lost: $at');
    }
    detector.reset();
    final replay = detector.inspect(
      File('test_support/generated/content_filter/speech.wav').absolute.path,
      startMs: 0,
    );
    if (replay?.word != '澳门') throw StateError('Reset did not allow replay');
    stdout.writeln(
      'Overlapping keyword: ${hit!.word} at ${at}ms; reset replay passed',
    );
  } finally {
    detector.close();
    await directory.delete(recursive: true);
  }
}
