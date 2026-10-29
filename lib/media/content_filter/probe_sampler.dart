import 'dart:io';
import '../../core/network/cancellation_token.dart';
import 'filter_types.dart';
import 'native_media_commands.dart';

/// Extracts bounded analysis data directly. Never encodes playback video.
final class ProbeSampler {
  ProbeSampler({
    required this.trusted,
    required this.playlist,
    required this.visual,
    required this.audio,
    this.frameStepMs = 500,
  });
  final bool Function(Uri) trusted, playlist;
  final bool visual, audio;
  final int frameStepMs;
  final _commands = NativeMediaCommands();
  Uri? _probedInput;
  bool _hasVisual = true, _hasAudio = true;

  Future<void> _resolveTracks(Uri input, CancellationToken token) async {
    if (!visual || !audio || _probedInput == input) return;
    final info = await _commands.probe(
      input.toString(),
      'http,tcp,crypto',
      token,
      hls: playlist(input),
    );
    token.check();
    final streams = (info['streams'] as List? ?? []).cast<Map>();
    _hasVisual = streams.any((s) => s['codec_type'] == 'video');
    _hasAudio = streams.any((s) => s['codec_type'] == 'audio');
    if (!_hasVisual && !_hasAudio) {
      throw const FilterFailure('没有可检测的音视频轨道');
    }
    _probedInput = input;
  }

  Future<MediaSlice> sample(
    Uri input,
    Duration start,
    Duration length,
    Directory directory,
    CancellationToken token,
  ) async {
    if (input.scheme != 'http' ||
        input.host != '127.0.0.1' ||
        !trusted(input)) {
      throw const FilterFailure('检测只接受受控媒体网关输入');
    }
    await _resolveTracks(input, token);
    await directory.create(recursive: true);
    final sound = audio && _hasAudio
        ? File('${directory.path}/audio.wav')
        : null;
    await _commands.run([
      '-protocol_whitelist',
      'http,tcp,crypto',
      '-format_whitelist',
      'hls,mov,flv,mpegts',
      if (playlist(input)) ...NativeMediaCommands.hlsOptions,
      '-threads',
      '1',
      '-ss',
      _seconds(start),
      '-i',
      input.toString(),
      if (visual && _hasVisual) ...[
        '-t',
        _seconds(length),
        '-map',
        '0:v:0',
        '-an',
        '-sn',
        '-dn',
        '-vf',
        'fps=${1000 / frameStepMs},scale=640:-2',
        '-threads',
        '1',
        '${directory.path}/frame_%03d.jpg',
      ],
      if (sound != null) ...[
        '-t',
        _seconds(length),
        '-map',
        '0:a:0',
        '-vn',
        '-sn',
        '-dn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        '-threads',
        '1',
        sound.path,
      ],
    ], token);
    token.check();
    final frames = await directory
        .list()
        .where((f) => f is File && f.path.endsWith('.jpg'))
        .cast<File>()
        .toList();
    frames.sort((a, b) => a.path.compareTo(b.path));
    return MediaSlice(
      directory: directory,
      media: File('${directory.path}/unused.ts'),
      frames: frames,
      audio: sound,
      start: start,
      duration: length,
    );
  }

  String _seconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(3);
}
