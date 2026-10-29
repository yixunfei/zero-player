import 'dart:io';
import '../../core/network/media_http_client.dart';
import 'approved_media_server.dart';
import 'declared_ad_sampler.dart';
import 'ffmpeg_slice_sampler.dart';
import 'filter_session.dart';
import 'filter_types.dart';
import 'filter_strategy.dart';
import 'local_models.dart';
import 'optional_resources.dart';
import 'fingerprints/feature_rule.dart';
import 'fingerprints/feature_inspector.dart';
import 'offline_inspector.dart';
import '../hls/timeline.dart';
import 'background_filter.dart';
import 'probe_sampler.dart';

final class ContentFilterService {
  ContentFilterService(
    this.root,
    MediaHttpClient http, {
    required this.isTrustedInput,
    required this.isPlaylist,
    OptionalResources? resources,
  }) : resources = resources ?? OptionalResources(root, http);
  final Directory root;
  final bool Function(Uri) isTrustedInput;
  final bool Function(Uri) isPlaylist;
  final OptionalResources resources;
  LocalModels get models => resources.models;
  final _enhanced = <FilterSession>{};
  final server = ApprovedMediaServer();
  final _sessions = <FilterSession>{};
  final _background = <BackgroundFilter>{};
  bool _closed = false;

  Future<BackgroundFilter?> createBackground(
    Uri input,
    Duration start, {
    required List<FeatureRule> rules,
    required bool keywords,
    required bool ocr,
    required bool asr,
    required int skipSeconds,
    FilterStrategy strategy = FilterStrategy.conservative,
    required void Function(String) onStatus,
    required void Function(FilterDetection) onHit,
    void Function(String)? onDiagnostic,
  }) async {
    if (_closed || !isTrustedInput(input)) throw const FilterFailure('检测会话不可用');
    final enabled = rules.where((rule) => rule.enabled).toList();
    // Missing optional resources never make a playable channel fail.
    final wantsKeywords = keywords;
    keywords =
        keywords &&
        !resources.busy &&
        await resources.installed(Enhancement.keywords);
    ocr = ocr && !resources.busy && await resources.installed(Enhancement.ocr);
    asr = asr && !resources.busy && await resources.installed(Enhancement.asr);
    if (_closed) return null;
    if (resources.busy) {
      keywords = false;
      ocr = false;
      asr = false;
    }
    if (enabled.isEmpty && !keywords && !ocr && !asr) {
      onStatus(
        wantsKeywords
            ? '正在播放 · 常见词语音资源未安装，请在设置中下载；也可标注音频样本'
            : '正在播放 · 本渠道暂无启用特征',
      );
      return null;
    }
    final enhanced = keywords || ocr || asr;
    if (enhanced) resources.users++;
    try {
      final rootDirectory = Directory('${root.path}/background');
      await rootDirectory.create(recursive: true);
      final directory = await rootDirectory.createTemp('filter_');
      final sampler = ProbeSampler(
        trusted: isTrustedInput,
        playlist: isPlaylist,
        visual: ocr || enabled.any((r) => r.usesVisual),
        audio: keywords || asr || enabled.any((r) => r.usesAudio),
        frameStepMs: 250,
      );
      final session = BackgroundFilter(
        input: input,
        directory: directory,
        sample: sampler.sample,
        start: start,
        overlap: enabled.isEmpty
            ? Duration.zero
            : const Duration(milliseconds: 500),
        lookBehind: enabled.fold<Duration>(
          Duration.zero,
          (value, rule) => value > Duration(milliseconds: rule.reacquireMs)
              ? value
              : Duration(milliseconds: rule.reacquireMs),
        ),
        inspector: FeatureInspector(
          enabled,
          strategy: strategy,
          denseSampling: true,
          enhancement: enhanced
              ? OfflineInspector(
                  models,
                  runtime: resources.runtime,
                  ocr: ocr,
                  asr: asr,
                  keywords: keywords ? resources.keywords : null,
                  skipSeconds: skipSeconds,
                )
              : null,
        ),
        onStatus: onStatus,
        onHit: onHit,
        onDiagnostic: onDiagnostic,
      );
      _background.add(session);
      if (enhanced) _backgroundEnhanced.add(session);
      if (_closed) {
        await releaseBackground(session);
        return null;
      }
      return session;
    } catch (_) {
      if (enhanced) resources.users--;
      rethrow;
    }
  }

  final _backgroundEnhanced = <BackgroundFilter>{};

  Future<void> releaseBackground(BackgroundFilter session) async {
    if (!_background.remove(session)) return;
    try {
      await session.close();
    } finally {
      if (_backgroundEnhanced.remove(session)) resources.users--;
    }
  }

  Future<FilterSession> create(
    Uri input,
    Duration start, {
    List<RemovedInterval> Function()? declaredAds,
    List<FeatureRule> rules = const [],
    bool ocr = false,
    bool asr = false,
  }) async {
    if (_closed || !isTrustedInput(input)) {
      throw const FilterFailure('媒体检测会话不可用');
    }
    if ((ocr || asr) && resources.busy) {
      throw const FilterFailure('增强资源正在修改，请稍后播放');
    }
    final enhanced = ocr || asr;
    if (enhanced) resources.users++;
    try {
      await server.start();
      final sessions = Directory('${root.path}/sessions');
      await sessions.create(recursive: true);
      final directory = await sessions.createTemp('filter_');
      if (_closed) {
        await directory.delete(recursive: true);
        throw const FilterFailure('媒体检测服务已关闭');
      }
      final sampler = FfmpegSliceSampler(
        isTrustedInput: isTrustedInput,
        isPlaylist: isPlaylist,
      );
      final session = FilterSession(
        input: input,
        directory: directory,
        start: start,
        declaredAds: declaredAds,
        sampler: declaredAds == null
            ? sampler
            : DeclaredAdSampler(sampler, declaredAds),
        inspector: FeatureInspector(
          rules,
          enhancement: ocr || asr
              ? OfflineInspector(
                  models,
                  runtime: resources.runtime,
                  ocr: ocr,
                  asr: asr,
                )
              : null,
        ),
      );
      _sessions.add(session);
      if (ocr || asr) {
        _enhanced.add(session);
      }
      return session;
    } catch (_) {
      if (enhanced) resources.users--;
      rethrow;
    }
  }

  Future<void> release(FilterSession session) async {
    server.unregister(session);
    _sessions.remove(session);
    try {
      await session.close();
    } finally {
      if (_enhanced.remove(session)) resources.users--;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final session in _background.toList()) {
      await releaseBackground(session);
    }
    for (final session in _sessions.toList()) {
      await release(session);
    }
    await server.close();
  }
}
