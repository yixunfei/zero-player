import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/hls/ts_timestamps.dart';

void main() {
  test(
    'reset PTS DTS and PCR move together without changing media payload',
    () {
      final input = _packet(pts: 129600, dts: 126000, pcr: 120000);
      final output = normalizeTsTimestamps(input, const Duration(seconds: 40));
      expect(_time(output, 21), 3729600);
      expect(_time(output, 26), 3726000);
      final pcr =
          output[6] << 25 |
          output[7] << 17 |
          output[8] << 9 |
          output[9] << 1 |
          output[10] >> 7;
      expect(pcr, 3720000);
      expect(output[10] & 0x7f, input[10] & 0x7f);
      expect(output.sublist(31), input.sublist(31));
      expect(_time(input, 26), 126000);
    },
  );
  test('invalid or scrambled transport passes through unchanged', () {
    final invalid = Uint8List.fromList([0, 1, 2]);
    expect(normalizeTsTimestamps(invalid, Duration.zero), same(invalid));
    final scrambled = _packet(pts: 126000, dts: 126000, pcr: 126000)
      ..[3] |= 0x80;
    expect(normalizeTsTimestamps(scrambled, Duration.zero), same(scrambled));
  });
  test('timestamps wrap in their 33 bit domain', () {
    final input = _packet(pts: 126000, dts: 126000, pcr: 126000);
    final start = Duration(seconds: (1 << 33) ~/ 90000 + 5);
    final out = normalizeTsTimestamps(input, start);
    expect(_time(out, 21), (start.inSeconds * 90000 + 126000) % (1 << 33));
  });
}

Uint8List _packet({required int pts, required int dts, required int pcr}) {
  final data = Uint8List(188)..fillRange(0, 188, 0x55);
  data.setAll(0, [0x47, 0x41, 0, 0x30, 7, 0x10]);
  data.setAll(6, [
    (pcr >> 25) & 255,
    (pcr >> 17) & 255,
    (pcr >> 9) & 255,
    (pcr >> 1) & 255,
    ((pcr & 1) << 7) | 0x7e,
    0,
  ]);
  data.setAll(12, [0, 0, 1, 0xe0, 0, 0, 0x80, 0xc0, 10]);
  _put(data, 21, pts, 0x30);
  _put(data, 26, dts, 0x10);
  return data;
}

void _put(Uint8List data, int at, int value, int prefix) => data.setAll(at, [
  prefix | ((value >> 29) & 14) | 1,
  (value >> 22) & 255,
  ((value >> 14) & 254) | 1,
  (value >> 7) & 255,
  ((value << 1) & 254) | 1,
]);
int _time(Uint8List data, int at) =>
    ((data[at] >> 1) & 7) << 30 |
    data[at + 1] << 22 |
    (data[at + 2] >> 1) << 15 |
    data[at + 3] << 7 |
    data[at + 4] >> 1;
