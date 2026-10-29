import 'dart:io';

import '../../core/network/cancellation_token.dart';
import '../hls/timeline.dart';
import 'filter_types.dart';

/// The gateway removes paired CUE ranges before FFmpeg sees the playlist.
/// Sampling uses that shortened source; all public positions remain original.
final class DeclaredAdSampler implements SliceSampler {
  DeclaredAdSampler(this.delegate, this.removed);
  final SliceSampler delegate;
  final List<RemovedInterval> Function() removed;
  MediaTimeline get _timeline => MediaTimeline(removed());

  @override
  Future<Duration> duration(Uri input, CancellationToken token) async {
    final processed = await delegate.duration(input, token);
    return _timeline.toOriginal(processed);
  }

  @override
  Future<MediaSlice> sample(
    Uri input,
    Duration start,
    Duration duration,
    Directory directory,
    CancellationToken token,
  ) async {
    final timeline = _timeline;
    final processed = timeline.toProcessed(start);
    if (timeline.toProcessed(start + duration) - processed != duration) {
      throw const FilterFailure('采样范围跨越已删除广告，已停止放行');
    }
    final slice = await delegate.sample(
      input,
      processed,
      duration,
      directory,
      token,
    );
    return MediaSlice(
      directory: slice.directory,
      media: slice.media,
      frames: slice.frames,
      audio: slice.audio,
      start: start,
      duration: slice.duration,
    );
  }

  @override
  Future<MediaSlice> crop(
    MediaSlice slice,
    Duration start,
    Duration length,
    CancellationToken token,
  ) => delegate.crop(slice, start, length, token);

  @override
  Future<File> publish(
    MediaSlice slice,
    Duration outputStart,
    CancellationToken token,
  ) => delegate.publish(slice, outputStart, token);
}
