import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import 'filter_types.dart';

final class TextRegion {
  const TextRegion(this.left, this.top, this.width, this.height);
  final int left;
  final int top;
  final int width;
  final int height;
}

/// PP-OCRv4 CPU inference. Invoke only inside the dedicated detector isolate.
final class PaddleOcr {
  PaddleOcr(String directory) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()..setIntraOpNumThreads(2);
    try {
      // Buffer loading also supports non-ASCII Windows profile paths.
      _detector = OrtSession.fromBuffer(
        File('$directory/det.onnx').readAsBytesSync(),
        options,
      );
      _recognizer = OrtSession.fromBuffer(
        File('$directory/rec.onnx').readAsBytesSync(),
        options,
      );
      _characters = [
        '',
        ..._recognizer!.getMetadatas('character').split('\n'),
        ' ',
      ];
      if (_characters.length != 6625) {
        throw const FilterFailure('OCR 字符表校验失败');
      }
    } catch (_) {
      close();
      rethrow;
    } finally {
      options.release();
    }
  }

  OrtSession? _detector;
  OrtSession? _recognizer;
  late final List<String> _characters;

  List<ContentEvidence> recognize(String path) {
    final source = img.decodeImage(File(path).readAsBytesSync());
    if (source == null || source.width < 16 || source.height < 16) {
      throw const FilterFailure('画面样本无法解码');
    }
    final regions = _regions(source);
    if (regions.length > 64) throw const FilterFailure('画面文字过密，无法可靠检查');
    return [for (final region in regions) _readRegion(source, region)];
  }

  ContentEvidence _readRegion(img.Image source, TextRegion region) {
    final crop = img.copyCrop(
      source,
      x: region.left,
      y: region.top,
      width: region.width,
      height: region.height,
    );
    final width = (48 * crop.width / crop.height).ceil().clamp(16, 1280);
    final resized = img.copyResize(crop, width: width, height: 48);
    final data = _normalized(resized, detection: false);
    final result = _run(_recognizer!, data, [1, 3, 48, width]);
    final rows = (result as List).first as List;
    final text = StringBuffer();
    var previous = -1;
    var confidence = 0.0;
    var characters = 0;
    for (final row in rows) {
      final values = row as List;
      if (values.length != _characters.length) {
        throw const FilterFailure('OCR 输出尺寸不正确');
      }
      var best = 0;
      for (var i = 1; i < values.length; i++) {
        if ((values[i] as num) > (values[best] as num)) best = i;
      }
      if (best != 0 && best != previous) {
        text.write(_characters[best]);
        confidence += (values[best] as num).toDouble();
        characters++;
      }
      previous = best;
    }
    return ContentEvidence(
      text: text.toString(),
      source: EvidenceSource.screen,
      confidence: characters == 0 ? 0 : confidence / characters,
      heightRatio: region.height / source.height,
    );
  }

  List<TextRegion> _regions(img.Image source) {
    final scale = math.min(1.0, 640 / math.max(source.width, source.height));
    final width = math.max(32, (source.width * scale / 32).round() * 32);
    final height = math.max(32, (source.height * scale / 32).round() * 32);
    final resized = img.copyResize(source, width: width, height: height);
    final result = _run(_detector!, _normalized(resized, detection: true), [
      1,
      3,
      height,
      width,
    ]);
    final map = (((result as List).first as List).first as List);
    if (map.length != height || (map.first as List).length != width) {
      throw const FilterFailure('文字检测输出尺寸不正确');
    }
    final mask = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = map[y] as List;
      for (var x = 0; x < width; x++) {
        if ((row[x] as num) >= 0.3) mask[y * width + x] = 1;
      }
    }
    final boxes = <TextRegion>[];
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0) continue;
      final region = _component(mask, width, height, i);
      if (region.width < 3 || region.height < 3) continue;
      boxes.add(_expand(region, source, width, height));
      if (boxes.length > 64) break;
    }
    boxes.sort((a, b) => a.top.compareTo(b.top));
    return boxes;
  }

  TextRegion _component(Uint8List mask, int width, int height, int seed) {
    final queue = <int>[seed];
    mask[seed] = 0;
    var left = seed % width, right = left;
    var top = seed ~/ width, bottom = top;
    for (var head = 0; head < queue.length; head++) {
      final cell = queue[head];
      final x = cell % width, y = cell ~/ width;
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
          final next = ny * width + nx;
          if (mask[next] != 0) {
            mask[next] = 0;
            queue.add(next);
          }
        }
      }
    }
    return TextRegion(left, top, right - left + 1, bottom - top + 1);
  }

  TextRegion _expand(TextRegion box, img.Image source, int width, int height) {
    final pad = math.max(2, box.height * 0.5);
    final x1 = ((box.left - pad) * source.width / width).floor().clamp(
      0,
      source.width - 1,
    );
    final y1 = ((box.top - pad) * source.height / height).floor().clamp(
      0,
      source.height - 1,
    );
    final x2 = ((box.left + box.width + pad) * source.width / width)
        .ceil()
        .clamp(x1 + 1, source.width);
    final y2 = ((box.top + box.height + pad) * source.height / height)
        .ceil()
        .clamp(y1 + 1, source.height);
    return TextRegion(x1, y1, x2 - x1, y2 - y1);
  }

  Float32List _normalized(img.Image image, {required bool detection}) {
    final plane = image.width * image.height;
    final result = Float32List(plane * 3);
    const means = [0.485, 0.456, 0.406];
    const deviations = [0.229, 0.224, 0.225];
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final bgr = [pixel.b, pixel.g, pixel.r];
        for (var c = 0; c < 3; c++) {
          final value = bgr[c] / 255;
          result[c * plane + y * image.width + x] = detection
              ? (value - means[c]) / deviations[c]
              : (value - 0.5) / 0.5;
        }
      }
    }
    return result;
  }

  Object? _run(OrtSession session, Float32List data, List<int> shape) {
    final tensor = OrtValueTensor.createTensorWithDataList(data, shape);
    final options = OrtRunOptions();
    List<OrtValue?> results = [];
    try {
      results = session.run(options, {session.inputNames.single: tensor});
      if (results.isEmpty || results.first == null) {
        throw const FilterFailure('OCR 推理没有返回结果');
      }
      return results.first!.value;
    } finally {
      for (final result in results) {
        result?.release();
      }
      tensor.release();
      options.release();
    }
  }

  void close() {
    _detector?.release();
    _recognizer?.release();
    _detector = null;
    _recognizer = null;
  }
}
