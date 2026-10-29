import 'dart:math' as math;
import 'dart:typed_data';

const audioBands = 24;
const audioStepMs = 250;
const _fftSize = 512;
// Fixed analysis geometry: calculate transcendental values once per isolate.
final _window = Float64List.fromList(
  List.generate(
    _fftSize,
    (i) => .5 - .5 * math.cos(2 * math.pi * i / (_fftSize - 1)),
  ),
);
final _bandForBin = List.generate(
  220,
  (bin) => bin < 3
      ? 0
      : (math.log(bin / 3) / math.log(220 / 3) * audioBands).floor().clamp(
          0,
          audioBands - 1,
        ),
);
final _fftCosines = _twiddles(math.cos);
final _fftSines = _twiddles(math.sin);

Float64List _twiddles(double Function(double) function) {
  final values = Float64List(_fftSize);
  for (var length = 2; length <= _fftSize; length <<= 1) {
    final angle = -2 * math.pi / length;
    for (var j = 0; j < length ~/ 2; j++) {
      values[length ~/ 2 + j] = function(angle * j);
    }
  }
  return values;
}

/// Reads only the bounded PCM16 / mono / 16 kHz WAV emitted by our sampler.
Float64List readPcmWave(Uint8List bytes) {
  if (bytes.length < 44 || bytes.length > 2 * 1024 * 1024) {
    throw const FormatException('音频样本长度无效');
  }
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('音频格式无效');
  }
  var validFormat = false;
  for (var cursor = 12; cursor + 8 <= bytes.length;) {
    final size = data.getUint32(cursor + 4, Endian.little);
    final start = cursor + 8, end = start + size;
    if (end > bytes.length) throw const FormatException('音频数据不完整');
    if (tag(cursor) == 'fmt ') {
      validFormat =
          size >= 16 &&
          data.getUint16(start, Endian.little) == 1 &&
          data.getUint16(start + 2, Endian.little) == 1 &&
          data.getUint32(start + 4, Endian.little) == 16000 &&
          data.getUint16(start + 14, Endian.little) == 16;
    } else if (tag(cursor) == 'data') {
      if (!validFormat || size % 2 != 0) {
        throw const FormatException('音频采样参数无效');
      }
      return Float64List.fromList(
        List.generate(
          size ~/ 2,
          (i) => data.getInt16(start + i * 2, Endian.little) / 32768,
        ),
      );
    }
    cursor = end + (size & 1);
  }
  throw const FormatException('音频没有 PCM 数据');
}

List<List<int>> audioFingerprint(Float64List pcm, {int stepMs = audioStepMs}) {
  if (stepMs < 50 || stepMs > 250) throw ArgumentError.value(stepMs);
  final result = <List<int>>[];
  final real = Float64List(_fftSize), imaginary = Float64List(_fftSize);
  for (var offset = 0; offset + 4000 <= pcm.length; offset += stepMs * 16) {
    final bands = List.filled(audioBands, 0.0);
    var energy = 0.0;
    for (var k = 0; k < 4000; k++) {
      energy += pcm[offset + k] * pcm[offset + k];
    }
    if (energy / 4000 < 1e-6) {
      result.add(List.filled(audioBands, 0));
      continue;
    }
    for (var part = 0; part + 512 <= 4000; part += 512) {
      imaginary.fillRange(0, _fftSize, 0);
      for (var i = 0; i < 512; i++) {
        real[i] = pcm[offset + part + i] * _window[i];
      }
      _fft(real, imaginary);
      for (var bin = 3; bin < 220; bin++) {
        final band = _bandForBin[bin];
        bands[band] += real[bin] * real[bin] + imaginary[bin] * imaginary[bin];
      }
    }
    final peak = bands.reduce(math.max);
    if (peak <= 1e-12 || !peak.isFinite) {
      result.add(List.filled(audioBands, 0));
      continue;
    }
    result.add(
      bands
          .map(
            (v) => (math.log(1 + 100 * v / peak) / math.log(101) * 255).round(),
          )
          .toList(),
    );
  }
  return result;
}

void _fft(Float64List real, Float64List imaginary) {
  final n = real.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final value = real[i];
      real[i] = real[j];
      real[j] = value;
    }
  }
  for (var length = 2; length <= n; length <<= 1) {
    for (var start = 0; start < n; start += length) {
      for (var j = 0; j < length ~/ 2; j++) {
        final a = start + j, b = a + length ~/ 2;
        final cosine = _fftCosines[length ~/ 2 + j];
        final sine = _fftSines[length ~/ 2 + j];
        final r = real[b] * cosine - imaginary[b] * sine;
        final im = real[b] * sine + imaginary[b] * cosine;
        real[b] = real[a] - r;
        imaginary[b] = imaginary[a] - im;
        real[a] += r;
        imaginary[a] += im;
      }
    }
  }
}

double audioSimilarity(List<int> a, List<int> b) {
  if (a.every((v) => v == 0) || b.every((v) => v == 0)) return 0;
  var difference = 0;
  for (var i = 0; i < audioBands; i++) {
    difference += (a[i] - b[i]).abs();
  }
  return 1 - difference / (audioBands * 255);
}

bool informativeAudio(List<List<int>> frames) {
  final active = frames.where((f) => f.any((v) => v > 0)).toList();
  if (active.length < 4) return false;
  return active
      .skip(1)
      .any((frame) => audioSimilarity(active.first, frame) < .96);
}
