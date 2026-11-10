import 'dart:async';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../core/network/request_scheduler.dart';
import '../domain/music_track.dart';
import 'music_repository.dart';

typedef MusicAudioSample = ({
  MusicTrack track,
  Duration latency,
  bool lossless,
  int mp3Kbps,
});

Future<MusicAudioSample> probeMusicAudio(
  MusicRepository repository,
  MusicTrack track,
  CancellationToken token,
) async {
  final watch = Stopwatch()..start();
  final resolved = await repository.resolve(track, token);
  if (!repository.allowed(resolved)) throw const FormatException('歌曲已被过滤');
  final payload = await repository.client.network.http.open(
    resolved.url,
    policy: HeaderPolicy({resolved.url: repository.headers(resolved)}),
    range: 'bytes=0-2047',
    cancellation: token,
    priority: RequestPriority.background,
  );
  final type =
      payload.response.headers['content-type']?.firstOrNull
          ?.split(';')
          .first
          .trim()
          .toLowerCase() ??
      '';
  if (!{200, 206}.contains(payload.response.statusCode) ||
      payload.uri.path.toLowerCase().endsWith('/404.mp3') ||
      (type.isNotEmpty &&
          !type.startsWith('audio/') &&
          !{
            'application/octet-stream',
            'application/ogg',
            'video/mp4',
          }.contains(type))) {
    await payload.body.take(0).drain<void>();
    throw const FormatException('歌曲地址未返回音频');
  }
  final bytes = await payload.body.firstWhere((chunk) => chunk.isNotEmpty);
  final prefix = String.fromCharCodes(bytes.take(12));
  final lossless =
      prefix.startsWith('fLaC') ||
      (prefix.startsWith('RIFF') && prefix.endsWith('WAVE')) ||
      {'audio/flac', 'audio/x-flac', 'audio/alac'}.contains(type);
  final recognizable =
      lossless ||
      prefix.startsWith('ID3') ||
      prefix.startsWith('OggS') ||
      (prefix.length >= 8 && prefix.substring(4, 8) == 'ftyp') ||
      (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0);
  if (!recognizable &&
      (!type.startsWith('audio/') || prefix.trimLeft().startsWith('<'))) {
    throw const FormatException('无法识别歌曲音频');
  }
  token.check();
  return (
    track: resolved,
    latency: watch.elapsed,
    lossless: lossless,
    mp3Kbps: _mp3Kbps(bytes),
  );
}

int _mp3Kbps(List<int> bytes) {
  var start = 0;
  if (bytes.length >= 10 && String.fromCharCodes(bytes.take(3)) == 'ID3') {
    // ID3v2 uses four seven-bit bytes for the tag length.
    for (final byte in bytes.getRange(6, 10)) {
      if (byte > 127) return 0;
      start = (start << 7) + byte;
    }
    start += 10;
    if (bytes[3] == 4 && bytes[5] & 0x10 != 0) start += 10;
  }
  if (start + 4 > bytes.length ||
      bytes[start] != 0xff ||
      bytes[start + 1] & 0xe6 != 0xe2) {
    return 0;
  }
  final version = (bytes[start + 1] >> 3) & 3;
  final index = bytes[start + 2] >> 4;
  if (version == 1 || bytes[start + 2] & 0x0c == 0x0c) return 0;
  const mpeg1 = [
    0,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
    0,
  ];
  const mpeg2 = [
    0,
    8,
    16,
    24,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    144,
    160,
    0,
  ];
  return (version == 3 ? mpeg1 : mpeg2)[index];
}
