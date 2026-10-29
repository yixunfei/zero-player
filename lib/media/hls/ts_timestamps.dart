import 'dart:typed_data';

const _wrap = 1 << 33;

/// Repairs a standalone MPEG-TS segment's clock, preserving encoded payloads
/// and the relative A/V timestamps. Invalid/encrypted transport stays untouched.
/// The caller must supply a finite VOD manifest's EXTINF start, never a guess
/// based on the current playhead or on whether a segment looks like an advert.
Uint8List normalizeTsTimestamps(Uint8List bytes, Duration start) {
  final origin = _origin(bytes);
  if (origin == null) return bytes;
  // Keep a positive lead-in for B frames and audio preroll. mpv subtracts the
  // common start time; subsequent segments retain their manifest coordinates.
  final target = (start.inMicroseconds * 90000 ~/ 1000000) + 126000;
  final offset = target - origin;
  if (offset == 0) return bytes;
  final output = Uint8List.fromList(bytes);
  for (var packet = 0; packet < output.length; packet += 188) {
    _shiftPacket(output, packet, offset);
  }
  return output;
}

int? _origin(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length % 188 != 0) return null;
  int? video, audio;
  for (var packet = 0; packet < bytes.length; packet += 188) {
    if (bytes[packet] != 0x47 ||
        bytes[packet + 1] & 0x80 != 0 ||
        bytes[packet + 3] & 0xc0 != 0) {
      return null;
    }
    final payload = _pes(bytes, packet);
    if (payload == null) continue;
    final stream = bytes[payload + 3];
    final flags = bytes[payload + 7] & 0xc0;
    final timestamp = flags == 0xc0 ? payload + 14 : payload + 9;
    if (!_validTimestamp(bytes, timestamp, packet + 188)) return null;
    final value = _readTimestamp(bytes, timestamp);
    if (stream >= 0xe0 && stream <= 0xef) video ??= value;
    if (stream >= 0xc0 && stream <= 0xdf) audio ??= value;
  }
  return video ?? audio;
}

int? _pes(Uint8List data, int packet) {
  if (data[packet + 1] & 0x40 == 0) return null;
  final control = (data[packet + 3] >> 4) & 3;
  if (control != 1 && control != 3) return null;
  final payload = packet + 4 + (control == 3 ? 1 + data[packet + 4] : 0);
  if (payload + 14 > packet + 188 ||
      data[payload] != 0 ||
      data[payload + 1] != 0 ||
      data[payload + 2] != 1 ||
      data[payload + 6] & 0xc0 != 0x80) {
    return null;
  }
  final flags = data[payload + 7] & 0xc0;
  if (flags != 0x80 && flags != 0xc0) return null;
  final needed = flags == 0xc0 ? 10 : 5;
  if (data[payload + 8] < needed || payload + 9 + needed > packet + 188) {
    return null;
  }
  return payload;
}

bool _validTimestamp(Uint8List data, int at, int end) =>
    at + 5 <= end &&
    data[at] & 1 == 1 &&
    data[at + 2] & 1 == 1 &&
    data[at + 4] & 1 == 1;

int _readTimestamp(Uint8List data, int at) =>
    ((data[at] >> 1) & 7) << 30 |
    data[at + 1] << 22 |
    (data[at + 2] >> 1) << 15 |
    data[at + 3] << 7 |
    data[at + 4] >> 1;

void _shiftTimestamp(Uint8List data, int at, int offset) {
  final value = (_readTimestamp(data, at) + offset) % _wrap;
  data[at] = (data[at] & 0xf0) | ((value >> 29) & 0x0e) | 1;
  data[at + 1] = (value >> 22) & 0xff;
  data[at + 2] = ((value >> 14) & 0xfe) | 1;
  data[at + 3] = (value >> 7) & 0xff;
  data[at + 4] = ((value << 1) & 0xfe) | 1;
}

void _shiftPacket(Uint8List data, int packet, int offset) {
  final control = (data[packet + 3] >> 4) & 3;
  if ((control == 2 || control == 3) &&
      data[packet + 4] >= 7 &&
      data[packet + 4] <= 183) {
    final flags = data[packet + 5];
    if (flags & 0x10 != 0) _shiftPcr(data, packet + 6, offset);
    if (flags & 0x08 != 0 && data[packet + 4] >= (flags & 0x10 != 0 ? 13 : 7)) {
      _shiftPcr(data, packet + (flags & 0x10 != 0 ? 12 : 6), offset);
    }
  }
  final pes = _pes(data, packet);
  if (pes == null) return;
  _shiftTimestamp(data, pes + 9, offset);
  if (data[pes + 7] & 0xc0 == 0xc0) _shiftTimestamp(data, pes + 14, offset);
}

void _shiftPcr(Uint8List data, int at, int offset) {
  final base =
      data[at] << 25 |
      data[at + 1] << 17 |
      data[at + 2] << 9 |
      data[at + 3] << 1 |
      data[at + 4] >> 7;
  final value = (base + offset) % _wrap;
  data[at] = value >> 25;
  data[at + 1] = (value >> 17) & 0xff;
  data[at + 2] = (value >> 9) & 0xff;
  data[at + 3] = (value >> 1) & 0xff;
  data[at + 4] = (data[at + 4] & 0x7f) | ((value & 1) << 7);
}
