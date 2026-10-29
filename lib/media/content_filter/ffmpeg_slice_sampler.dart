import 'dart:io';
import '../../core/network/cancellation_token.dart';
import 'filter_types.dart';
import 'native_media_commands.dart';

/// Re-encoding avoids leaking rejected pre-roll through keyframe seeking.
/// The original stream is decoded only in this quarantined sampling pipeline.
final class FfmpegSliceSampler implements SliceSampler {
  FfmpegSliceSampler({
    required this.isTrustedInput,
    required this.isPlaylist,
    NativeMediaCommands? commands,
  }) : commands = commands ?? NativeMediaCommands();
  final bool Function(Uri) isTrustedInput;
  final bool Function(Uri) isPlaylist;
  final NativeMediaCommands commands;
  bool _hasAudio = false;

  void _validate(Uri uri) {
    if (uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        !isTrustedInput(uri)) {
      throw const FilterFailure('检测只接受受控媒体网关输入');
    }
  }

  @override
  Future<Duration> duration(Uri input, CancellationToken cancellation) async {
    _validate(input);
    final info = await commands.probe(
      input.toString(),
      'http,tcp,crypto',
      cancellation,
      hls: isPlaylist(input),
    );
    final streams = (info['streams'] as List?) ?? [];
    if (!streams.any((s) => (s as Map)['codec_type'] == 'video')) {
      throw const FilterFailure('媒体没有视频轨道，无法执行画面检查');
    }
    _hasAudio = streams.any((s) => (s as Map)['codec_type'] == 'audio');
    final video = streams.cast<Map>().firstWhere(
      (s) => s['codec_type'] == 'video',
    );
    final rawDuration =
        video['duration'] ?? (info['format'] as Map?)?['duration'];
    var seconds = double.tryParse('$rawDuration');
    if (seconds == null || !seconds.isFinite || seconds <= 0) {
      throw const FilterFailure('当前媒体无法确定点播时长，严格过滤已停止播放');
    }
    // FLV may report an AAC tail after the last complete video frame.
    if (video['duration'] == null) {
      final rate = (video['avg_frame_rate']?.toString() ?? '').split('/');
      final numerator = double.tryParse(rate.first) ?? 0;
      final denominator = rate.length == 2
          ? double.tryParse(rate.last) ?? 0
          : 0;
      if (numerator > 0 && denominator > 0) {
        final fps = numerator / denominator;
        seconds = ((seconds * fps) + 0.0001).floor() / fps;
      }
    }
    return Duration(microseconds: (seconds * 1000000).round());
  }

  @override
  Future<MediaSlice> sample(
    Uri input,
    Duration start,
    Duration duration,
    Directory directory,
    CancellationToken cancellation,
  ) async {
    _validate(input);
    await directory.create(recursive: true);
    final media = File('${directory.path}/sample.ts');
    await commands.run([
      '-protocol_whitelist',
      'http,tcp,crypto',
      '-format_whitelist',
      'hls,mov,flv,mpegts',
      if (isPlaylist(input)) ...NativeMediaCommands.hlsOptions,
      '-ss',
      _seconds(start),
      '-i',
      input.toString(),
      '-t',
      _seconds(duration),
      ..._encodingOptions,
      media.path,
    ], cancellation);
    cancellation.check();
    if (!await media.exists() || await media.length() == 0) {
      throw const FilterFailure('媒体采样为空，已停止放行');
    }
    final audio = _hasAudio ? File('${directory.path}/audio.wav') : null;
    await _extract(media, directory, audio, cancellation);
    final frames = await directory
        .list()
        .where((f) => f is File && f.path.endsWith('.png'))
        .cast<File>()
        .toList();
    frames.sort((a, b) => a.path.compareTo(b.path));
    final expected = (duration.inMicroseconds / 1e6 * 2).floor().clamp(1, 8);
    if (frames.length < expected || frames.length > 10) {
      throw const FilterFailure('画面采样不完整，已停止放行');
    }
    return MediaSlice(
      directory: directory,
      media: media,
      frames: frames,
      audio: audio,
      start: start,
      duration: duration,
    );
  }

  List<String> get _encodingOptions => [
    '-map',
    '0:v:0',
    '-map',
    '0:a:0?',
    '-sn',
    '-dn',
    '-threads',
    '2',
    '-vf',
    "scale=w='min(1280,iw)':h='min(720,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
    '-r',
    '25',
    '-c:v',
    'mpeg2video',
    '-q:v',
    '3',
    '-g',
    '25',
    '-bf',
    '0',
    '-pix_fmt',
    'yuv420p',
    if (_hasAudio) ...[
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-ar',
      '48000',
      '-ac',
      '2',
    ],
    '-muxdelay',
    '0',
    '-f',
    'mpegts',
  ];

  @override
  Future<MediaSlice> crop(
    MediaSlice slice,
    Duration start,
    Duration length,
    CancellationToken cancellation,
  ) async {
    if (start < slice.start ||
        length <= Duration.zero ||
        start + length > slice.start + slice.duration) {
      throw const FilterFailure('裁剪范围超出已检测片段');
    }
    final directory = await slice.directory.parent.createTemp('crop_');
    final media = File('${directory.path}/sample.ts');
    await commands.run([
      '-protocol_whitelist',
      'file',
      '-format_whitelist',
      'mpegts',
      '-ss',
      _seconds(start - slice.start),
      '-i',
      slice.media.path,
      '-t',
      _seconds(length),
      ..._encodingOptions,
      media.path,
    ], cancellation);
    cancellation.check();
    if (!await media.exists() || await media.length() == 0) {
      throw const FilterFailure('裁剪内容为空，已停止放行');
    }
    return MediaSlice(
      directory: directory,
      media: media,
      frames: const [],
      audio: null,
      start: start,
      duration: length,
    );
  }

  Future<void> _extract(
    File media,
    Directory directory,
    File? audio,
    CancellationToken cancellation,
  ) => commands.run([
    '-protocol_whitelist',
    'file',
    '-format_whitelist',
    'mpegts',
    '-i',
    media.path,
    '-map',
    '0:v:0',
    '-an',
    '-vf',
    'fps=2',
    '-frames:v',
    '10',
    '-threads',
    '2',
    '${directory.path}/frame_%03d.png',
    if (audio != null) ...[
      '-map',
      '0:a:0',
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'pcm_s16le',
      audio.path,
    ],
  ], cancellation);

  @override
  Future<File> publish(
    MediaSlice slice,
    Duration outputStart,
    CancellationToken cancellation,
  ) async {
    final output = File('${slice.directory.path}/approved.ts');
    await commands.run([
      '-protocol_whitelist',
      'file',
      '-format_whitelist',
      'mpegts',
      '-i',
      slice.media.path,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      '-c',
      'copy',
      '-output_ts_offset',
      _seconds(outputStart),
      '-muxdelay',
      '0',
      '-f',
      'mpegts',
      output.path,
    ], cancellation);
    cancellation.check();
    for (final file in [
      slice.media,
      ...slice.frames,
      if (slice.audio != null) slice.audio!,
    ]) {
      if (await file.exists()) await file.delete();
    }
    return output;
  }

  String _seconds(Duration value) =>
      (value.inMicroseconds / 1e6).toStringAsFixed(6);
}
