import 'dart:math' as math;
import 'package:image/image.dart' as img;

final class VisualFingerprint {
  const VisualFingerprint(this.bits, this.color, this.contrast);
  final String bits;
  final List<int> color;
  final double contrast;
  bool get informative => contrast >= 10;

  Map<String, Object> toJson() => {
    'bits': bits,
    'color': color,
    'contrast': contrast,
  };
  factory VisualFingerprint.fromJson(Map data) {
    final bits = data['bits'];
    final color = data['color'];
    final contrast = data['contrast'];
    if (bits is! String ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(bits) ||
        color is! List ||
        color.length != 3 ||
        color.any((v) => v is! int || v < 0 || v > 255) ||
        contrast is! num ||
        !contrast.isFinite ||
        contrast < 0 ||
        contrast > 128) {
      throw const FormatException('画面特征无效');
    }
    return VisualFingerprint(bits, color.cast<int>(), contrast.toDouble());
  }

  double similarity(VisualFingerprint other) {
    var distance = 0;
    for (var i = 0; i < bits.length; i++) {
      var xor =
          int.parse(bits[i], radix: 16) ^ int.parse(other.bits[i], radix: 16);
      while (xor != 0) {
        distance++;
        xor &= xor - 1;
      }
    }
    final chroma =
        List.generate(
          3,
          (i) => (color[i] - other.color[i]).abs(),
        ).reduce((a, b) => a + b) /
        (3 * 255);
    return (1 - distance / 64) * .85 + (1 - chroma) * .15;
  }
}

final _cosines = List.generate(
  8,
  (u) => List.generate(32, (x) => math.cos((2 * x + 1) * u * math.pi / 64)),
);

VisualFingerprint visualFingerprint(img.Image source) {
  final image = img.copyResize(
    source,
    width: 32,
    height: 32,
    interpolation: img.Interpolation.average,
  );
  final grey = <double>[];
  final color = [0.0, 0.0, 0.0];
  for (final pixel in image) {
    color[0] += pixel.r;
    color[1] += pixel.g;
    color[2] += pixel.b;
    grey.add(pixel.r * .299 + pixel.g * .587 + pixel.b * .114);
  }
  final mean = grey.reduce((a, b) => a + b) / grey.length;
  final contrast = math.sqrt(
    grey.fold(0.0, (sum, x) => sum + (x - mean) * (x - mean)) / grey.length,
  );
  final rows = List.generate(
    32,
    (y) => List.generate(8, (u) {
      var sum = 0.0;
      for (var x = 0; x < 32; x++) {
        sum += grey[y * 32 + x] * _cosines[u][x];
      }
      return sum;
    }),
  );
  final coefficients = List.generate(64, (i) {
    final u = i % 8, v = i ~/ 8;
    var sum = 0.0;
    for (var y = 0; y < 32; y++) {
      sum += rows[y][u] * _cosines[v][y];
    }
    return sum;
  });
  final ordered = coefficients.skip(1).toList()..sort();
  final median = ordered[ordered.length ~/ 2];
  final bits = StringBuffer();
  for (var group = 0; group < 16; group++) {
    var nibble = 0;
    for (var bit = 0; bit < 4; bit++) {
      final index = group * 4 + bit;
      if (index > 0 && coefficients[index] > median) nibble |= 1 << bit;
    }
    bits.write(nibble.toRadixString(16));
  }
  return VisualFingerprint(
    bits.toString(),
    color.map((v) => (v / 1024).round()).toList(),
    contrast,
  );
}
