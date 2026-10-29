import 'dart:io';
import 'dart:math';
import '../../../core/network/cancellation_token.dart';
import '../content_filter_service.dart';
import '../ffmpeg_slice_sampler.dart';
import '../probe_sampler.dart';
import '../filter_types.dart';
import 'feature_rule.dart';
import 'sample_signature.dart';
import 'feature_anchor.dart';
import 'anchor_extraction.dart';

final class FeatureCapture {
  FeatureCapture(this.service);
  final ContentFilterService service;

  Future<FeatureRule> capture(
    Uri input, {
    required String sourceId,
    required String originKey,
    required Duration from,
    required Duration to,
    Duration? originStart,
    Duration? knownDuration,
    required String label,
    required FeatureMode mode,
    required int beforeMs,
    required int afterMs,
    required CancellationToken token,
  }) async {
    final length = to - from;
    if (from < Duration.zero ||
        length.inMilliseconds < 1000 ||
        length.inMilliseconds > 600000) {
      throw const FilterFailure('请选择 1 秒至 10 分钟的完整片段，内部自动提取短特征');
    }
    final sampler = FfmpegSliceSampler(
      isTrustedInput: service.isTrustedInput,
      isPlaylist: service.isPlaylist,
    );
    final duration = knownDuration != null && knownDuration > Duration.zero
        ? knownDuration
        : await sampler.duration(input, token);
    final probe = ProbeSampler(
      trusted: service.isTrustedInput,
      playlist: service.isPlaylist,
      visual: mode != FeatureMode.audio,
      audio: mode != FeatureMode.visual,
    );
    if (to > duration) throw const FilterFailure('样本超出视频时长');
    final parent = Directory('${service.root.path}/captures');
    await parent.create(recursive: true);
    final directory = await parent.createTemp('capture_');
    try {
      final extracted = await _extract(
        probe,
        input,
        from,
        length,
        directory,
        mode,
        token,
      );
      token.check();
      final id = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final rule = FeatureRule(
        id: id,
        sourceId: sourceId,
        label: label.trim(),
        mode: mode,
        sampleMs: length.inMilliseconds,
        beforeMs: beforeMs,
        afterMs: afterMs,
        visual: extracted.$1.first.visual,
        audio: extracted.$1.first.audio,
        anchors: extracted.$1,
        thumbnail: extracted.$2,
        captureNote: extracted.$3,
        originKey: originKey,
        originStartMs: (originStart ?? from).inMilliseconds,
      );
      rule.validate();
      return rule;
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<(List<FeatureAnchor>, String, String)> _extract(
    ProbeSampler probe,
    Uri input,
    Duration from,
    Duration length,
    Directory directory,
    FeatureMode mode,
    CancellationToken token,
  ) async {
    final anchors = <FeatureAnchor>[];
    final windows = anchorWindows(length.inMilliseconds);
    var thumbnail = '', shortened = 0, rejected = 0;
    Object? lastFailure;
    for (final (offset, requested) in windows) {
      token.check();
      final work = Directory('${directory.path}/$offset');
      try {
        final slice = await probe.sample(
          input,
          from + Duration(milliseconds: offset),
          Duration(milliseconds: requested),
          work,
          token,
        );
        final signature = await sampleSignature(
          slice,
          preview: thumbnail.isEmpty,
          visual: mode != FeatureMode.audio,
          audio: mode != FeatureMode.visual,
        );
        final anchor = observedAnchor(
          signature,
          offsetMs: offset,
          requestedMs: requested,
          mode: mode,
        );
        anchors.add(anchor);
        if (anchor.durationMs < requested) shortened++;
        if (thumbnail.isEmpty) thumbnail = signature.thumbnail;
      } on Exception catch (error) {
        token.check();
        rejected++;
        lastFailure = error;
      } finally {
        if (await work.exists()) await work.delete(recursive: true);
      }
    }
    if (anchors.isEmpty) {
      throw lastFailure ?? const FilterFailure('没有可识别的有效内容');
    }
    final note =
        '已提取 ${anchors.length}/${windows.length} 个有效短特征；'
        '缩短 $shortened 个采样尾部，排除 $rejected 个低质量或不可读取样本。'
        '完整跳过边界保持所选范围，不补造声音。';
    return (anchors, thumbnail, note);
  }
}
