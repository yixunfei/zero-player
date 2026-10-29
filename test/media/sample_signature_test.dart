import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/content_filter/fingerprints/sample_signature.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('signature-'));
  tearDown(() async => root.delete(recursive: true));
  MediaSlice sample(List<File> frames, File? audio) => MediaSlice(
    directory: root,
    media: File('${root.path}/unused.ts'),
    frames: frames,
    audio: audio,
    start: Duration.zero,
    duration: const Duration(seconds: 4),
  );

  test('audio-only detection does not decode unused video frames', () async {
    final result = await sampleSignature(
      sample([File('${root.path}/not-decoded.png')], null),
      visual: false,
    );
    expect(result.visual, isEmpty);
    expect(result.audio, isEmpty);
  });

  test('visual-only detection does not read unused audio', () async {
    final frame = await File(
      '${root.path}/frame.png',
    ).writeAsBytes(img.encodePng(img.Image(width: 32, height: 32)));
    final result = await sampleSignature(
      sample([frame], File('${root.path}/not-decoded.wav')),
      audio: false,
    );
    expect(result.visual, hasLength(1));
    expect(result.audio, isEmpty);
  });
}
