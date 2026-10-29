import 'dart:convert';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import '../filter_types.dart';
import 'audio_fingerprint.dart';
import 'visual_fingerprint.dart';

final class SampleSignature {
  const SampleSignature(
    this.visual,
    this.audio,
    this.thumbnail, {
    this.visualStepMs = 500,
    this.audioStepMs = 250,
  });
  final List<VisualFingerprint> visual;
  final List<List<int>> audio;
  final String thumbnail;
  final int visualStepMs, audioStepMs;
}

Future<SampleSignature> sampleSignature(
  MediaSlice slice, {
  bool preview = false,
  bool visual = true,
  bool audio = true,
  int visualStepMs = 500,
  int audioStepMs = 250,
}) => Isolate.run(() async {
  final pictures = <VisualFingerprint>[];
  var thumbnail = '';
  final frames = visual
      ? slice.frames
      : preview
      ? slice.frames.take(1)
      : slice.frames.take(0);
  for (final file in frames) {
    final image = img.decodeImage(await file.readAsBytes());
    if (image == null) throw const FilterFailure('无法读取特征画面');
    if (visual) pictures.add(visualFingerprint(image));
    if (preview && thumbnail.isEmpty) {
      thumbnail = base64Encode(
        img.encodeJpg(img.copyResize(image, width: 240), quality: 55),
      );
    }
  }
  final sound = !audio || slice.audio == null
      ? <List<int>>[]
      : audioFingerprint(
          readPcmWave(await slice.audio!.readAsBytes()),
          stepMs: audioStepMs,
        );
  return SampleSignature(
    pictures,
    sound,
    thumbnail,
    visualStepMs: visualStepMs,
    audioStepMs: audioStepMs,
  );
});
