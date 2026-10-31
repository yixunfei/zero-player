import 'line_probe.dart';
import '../../../app/app_version.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../media/content_filter/fingerprints/feature_capture.dart';
import '../../../media/content_filter/fingerprints/feature_rule.dart';
import 'dart:async';
import 'dart:convert';
import '../../supervision/domain/supervision_rules.dart';
import 'package:flutter/foundation.dart';

import '../../../app/app_services.dart';
import '../../../core/network/header_policy.dart';
import '../../../media/gateway/media_gateway.dart';
import '../../../media/gateway/offline_server.dart';
import '../../../media/hls/timeline.dart';
import '../../../media/hls/hls_quality.dart';
import '../../../media/content_filter/background_filter.dart';
import '../../../media/content_filter/filter_types.dart';
import '../../../media/content_filter/filter_strategy.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/domain/vod_provider.dart';
import '../../catalog/data/provider_factory.dart';
import '../../../core/network/document_client.dart';
import '../data/skip_repository.dart';
import '../domain/player_engine.dart';
import '../domain/playback_mark_target.dart';
import '../domain/feature_work_identity.dart';
import 'playback_diagnostics.dart';
import 'filter_detection_queue.dart';

enum PlaybackMediaKind { online, live, downloaded, local }

final class PlaybackRequest {
  const PlaybackRequest(
    this.item, {
    this.line = 0,
    this.episode = 0,
    this.position = Duration.zero,
    this.live = false,
    this.headers = const {},
    this.headersByUri = const {},
    this.offline,
    this.quality,
    this.mediaKind,
  });
  final CatalogItem item;
  final int line;
  final int episode;
  final Duration position;
  final bool live;
  final Map<String, String> headers;
  final Map<Uri, Map<String, String>> headersByUri;
  final OfflineSession? offline;
  final Uri? quality;
  final PlaybackMediaKind? mediaKind;
  PlaybackMediaKind get kind =>
      mediaKind ??
      (live
          ? PlaybackMediaKind.live
          : offline == null
          ? PlaybackMediaKind.online
          : item.sourceId == 'local'
          ? PlaybackMediaKind.local
          : PlaybackMediaKind.downloaded);
  bool get supportsMarks =>
      kind == PlaybackMediaKind.online && !live && offline == null;
}

final class PlaybackController extends ChangeNotifier {
  PlaybackController(this.services, this.engine) {
    services.contentPolicy.addListener(_policyChanged);
    _states = engine.states.listen(_onState);
    _errors = engine.errors.listen((_) {
      if (!_switching && !_closed && !blocked) {
        error = request?.offline != null
            ? '本地媒体播放中断，请重试或检查文件是否可读'
            : '播放中断。可重试、切换线路或重新搜索其他来源';
        _scheduleRecovery();
        notifyListeners();
      }
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _policyChanged();
      unawaited(save());
    });
  }
  bool blocked = false;
  bool _allowed(PlaybackRequest next) {
    if (next.line < 0 || next.line >= next.item.lines.length) return false;
    return next.live
        ? services.contentPolicy.liveNameAllowed(
            next.item.lines[next.line].name,
          )
        : services.contentPolicy.itemAllowed(next.item);
  }

  void _policyChanged() {
    if (_closed || blocked || request == null || _allowed(request!)) return;
    blocked = true;
    _generation++;
    cancelRecovery();
    error = '内容已被成人过滤或监管规则屏蔽';
    _captureToken?.cancel();
    _contentSession?.cancel();
    _gateway?.close();
    request?.offline?.close();
    state = const PlaybackSnapshot();
    unawaited(engine.stop().catchError((Object _) {}));
    notifyListeners();
  }

  Future<void> _validate(PlaybackRequest next) async {
    if (!next.live) {
      await services.sources.find(next.item.sourceId);
    } else if (next.line >= 0 && next.line < next.item.lines.length) {
      final channel = services.contentPolicy.liveChannel(
        next.item.lines[next.line].name,
      );
      if (channel != null) await services.live.schedule(channel);
    }
    if (!_allowed(next)) throw const ContentBlocked();
  }

  final AppServices services;
  final PlayerEngine engine;
  late final StreamSubscription<PlaybackSnapshot> _states;
  late final StreamSubscription<String> _errors;
  late final Timer _saveTimer;
  PlaybackRequest? request;
  ResolvedMedia? resolvedMedia;
  PlaybackSnapshot state = const PlaybackSnapshot();
  GatewaySession? _gateway;
  BackgroundFilter? _contentSession;
  final _filterStarts = <Future<void>>{};
  final _detected = FilterDetectionQueue();
  List<FeatureRule> _originFeatures = [];
  List<FeatureRule> activeFeatures = const [];
  FilterDetection? pendingFeature;
  String get featureSeriesKey => featureWorkIdentity(request!.item);
  String get featureStatusSummary => !services.settings.value.contentFilter
      ? '内容特征检测未启用'
      : '本视频启用 ${activeFeatures.length} 条内容特征 · '
            '${FilterStrategy.parse(services.settings.value.filterStrategy).label}\n'
            '${filterStatus ?? '等待检测状态'}\n${filterDiagnostic ?? ''}';
  bool _filterSeeking = false;
  int _filterEpoch = 0;
  Uri? _playbackInput;
  String? filterStatus;
  String? filterDiagnostic;
  final diagnostics = PlaybackDiagnostics();
  String diagnosticReport() => diagnostics.report({
    '版本': appBuildVersion,
    '系统': defaultTargetPlatform.name,
    '影片': request?.item.title,
    '渠道 ID': request?.item.sourceId,
    '集数': request == null ? null : episode.label,
    '播放位置 ms': state.position.inMilliseconds,
    '待确认跳转 ms': _expectedSeek?.inMilliseconds,
    '检测当前位置 ms': _contentSession?.playbackPosition.inMilliseconds,
    '检测扫描位置 ms': _contentSession?.scanPosition.inMilliseconds,
    '原始位置 ms': originalPosition.inMilliseconds,
    '总时长 ms': state.duration.inMilliseconds,
    '内容过滤': services.settings.value.contentFilter,
    '状态': filterStatus,
    '扫描进度': filterDiagnostic,
    '时间轴': _gateway?.timestampStatus,
    '本集标记数': _originFeatures.length,
    '适用特征数': activeFeatures.length,
    '检测策略': services.settings.value.filterStrategy,
    '本集区间数': marks.length,
    '待命中区间数': _detected.length,
    '数据目录': services.root.path,
  });
  bool get strictFiltering => false;
  Future<void> _queue = Future.value();
  bool _switching = false;
  bool _closed = false;
  Future<void>? _closing;
  final _shutdown = Completer<void>();
  bool _advancing = false;
  int _generation = 0;
  Duration? _resume;
  String? routeWarning;
  final _routeToken = CancellationToken();
  bool _findingAlternative = false;
  void dismissRouteWarning() {
    routeWarning = null;
    notifyListeners();
  }

  Future<bool> switchAlternativeLine({CatalogItem? refreshed}) async {
    final current = request;
    if (_closed ||
        blocked ||
        busy ||
        _findingAlternative ||
        current == null ||
        current.live ||
        current.offline != null) {
      return false;
    }
    _findingAlternative = true;
    cancelRecovery();
    final generation = _generation;
    final label = episode.label;
    final candidate = refreshed ?? current.item;
    if (candidate.sourceId != current.item.sourceId ||
        candidate.id != current.item.id) {
      _findingAlternative = false;
      return false;
    }
    try {
      var checked = 0;
      for (var i = 0; i < candidate.lines.length && checked < 6; i++) {
        if (_closed || generation != _generation) return false;
        if (candidate.lines[i].name == line.name) continue;
        final episodes = candidate.lines[i].episodes;
        final matches = matchingEpisodes(label, episodes);
        if (matches.length != 1) continue;
        checked++;
        try {
          await probeEpisode(
            services,
            candidate,
            episodes[matches.single],
            _routeToken,
          );
        } catch (_) {
          continue;
        }
        if (_closed || generation != _generation || !_allowed(current)) {
          return false;
        }
        final saved = _resume ?? originalPosition;
        final playing = !_userPaused;
        final rate = state.rate;
        final opening = open(
          PlaybackRequest(
            candidate,
            line: i,
            episode: matches.single,
            position: saved,
          ),
          automatic: true,
        );
        final switchGeneration = _generation;
        await opening;
        if (_closed || switchGeneration != _generation) return false;
        if (error != null) return false;
        await engine.setRate(rate);
        if (_closed || switchGeneration != _generation) return false;
        if (!playing) await engine.pause();
        return true;
      }
      if (!_closed && generation == _generation) {
        routeWarning = '未找到通过检测的同集备用线路，请切换渠道或手动选线';
        notifyListeners();
      }
      return false;
    } finally {
      _findingAlternative = false;
    }
  }

  String? error;
  String? notice;
  List<SkipMark> marks = [];
  Duration? markStart;
  Duration? featureStart;
  CancellationToken? _captureToken;
  Future<void>? _captureFinished;
  Duration? _undoPosition;
  final _skipped = <String>{};
  double? _previousRate;
  Timer? _recoveryTimer;
  int _recoveryAttempts = 0;
  bool _recoveryCancelled = false;
  bool _userPaused = false;
  bool workSkipEnabled = true;
  String get seriesKey => '${request!.item.sourceId}|${request!.item.id}';
  bool get recovering => _recoveryTimer?.isActive ?? false;
  bool get canUndoSkip => _undoPosition != null;
  bool get canCancelRecovery =>
      !_recoveryCancelled && (notice?.startsWith('正在尝试恢复') ?? false);
  MediaTimeline get timeline => _gateway?.timeline ?? const MediaTimeline([]);
  Duration get originalPosition => timeline.toOriginal(state.position);
  Duration get originalDuration => timeline.toOriginal(state.duration);
  Duration get originalBuffer => timeline.toOriginal(state.buffer);
  PlayLine get line => request!.item.lines[request!.line];
  Episode get episode => line.episodes[request!.episode];
  String get workKey =>
      '${request!.item.sourceId}|${request!.item.id}|${line.name}|${episode.label}';
  List<HlsQuality> get qualities => _gateway?.qualities ?? const [];
  Future<void> changeQuality(Uri? quality) async {
    final current = request;
    if (_closed || current == null || busy || current.offline != null) return;
    final playing = state.playing;
    final rate = state.rate;
    await open(
      PlaybackRequest(
        current.item,
        line: current.line,
        episode: current.episode,
        position: originalPosition,
        live: current.live,
        headers: current.headers,
        headersByUri: current.headersByUri,
        quality: quality,
      ),
    );
    if (_closed) return;
    final generation = _generation;
    await engine.setRate(rate);
    if (_closed || generation != _generation) return;
    if (!playing) await engine.pause();
  }

  bool get busy => _switching;
  bool get userPaused => _userPaused;
  bool get isLive => request?.live ?? false;

  Future<void> open(PlaybackRequest next, {bool automatic = false}) {
    if (_closed) return Future.value();
    _captureToken?.cancel();
    _contentSession?.cancel();
    _filterEpoch++;
    _recoveryTimer?.cancel();
    if (!automatic) {
      _recoveryAttempts = 0;
      _recoveryCancelled = false;
      _userPaused = false;
    }
    final generation = ++_generation;
    _queue = _queue.catchError((Object _) {}).then((_) async {
      if (_closed || generation != _generation) return;
      await Future.any([_open(next, generation), _shutdown.future]);
    });
    return _queue;
  }

  Future<void> _open(PlaybackRequest next, int generation) async {
    await save();
    if (_closed || generation != _generation) return;
    _switching = true;
    error = null;
    routeWarning = null;
    notifyListeners();
    try {
      await services.pauseRadioForVideo();
      if (_closed || generation != _generation) return;
      await _seekQueue?.catchError((Object _) {});
      if (_closed || generation != _generation) return;
      await engine.stop();
      if (_closed || generation != _generation) return;
      await _closeContentFilter();
      if (_closed || generation != _generation) return;
      _gateway?.close();
      _gateway = null;
      if (request?.offline != next.offline) request?.offline?.close();
      request = next;
      await _validate(next);
      blocked = false;
      resolvedMedia = null;
      state = const PlaybackSnapshot();
      markStart = null;
      featureStart = null;
      _undoPosition = null;
      notice = null;
      _skipped.clear();
      _filterSeeking = false;
      _seekRevision++;
      _seekSettleTimer?.cancel();
      _expectedSeek = null;
      _resume = next.position > Duration.zero ? next.position : null;
      _advancing = false;
      marks = next.live || next.offline != null
          ? []
          : await services.skips.list(workKey);
      if (_closed || generation != _generation) return;
      workSkipEnabled = await services.skips.workEnabled(seriesKey);
      if (_closed || generation != _generation) return;
      final uri = next.offline?.uri ?? await _onlineUri(next);
      if (generation != _generation || _closed) return;
      await _validate(next);
      if (generation != _generation || _closed) return;
      _playbackInput = uri;
      await engine.open(uri);
      if (generation != _generation || _closed || !_allowed(next)) {
        await engine.stop();
        return;
      }
      _switching = false;
      _onState(engine.snapshot);
      if (services.settings.value.contentFilter && !next.live) {
        unawaited(_startContentFilter(uri, generation));
      }
    } catch (e) {
      if (_closed || generation != _generation) return;
      if (e is ContentBlocked) {
        blocked = true;
        cancelRecovery();
        _gateway?.close();
        next.offline?.close();
      }
      error = e is FilterFailure
          ? e.message
          : e is RemoteFailure
          ? e.message
          : e is FormatException
          ? e.message
          : next.offline != null
          ? '无法打开本地媒体，请检查文件是否存在及编码是否受支持'
          : '无法打开媒体。请检查来源，或切换线路后重试';
    } finally {
      if (generation == _generation && !_closed) {
        _switching = false;
        if (error != null) _scheduleRecovery();
        notifyListeners();
      }
    }
  }

  Future<Uri> _onlineUri(PlaybackRequest next) async {
    var media = episode;
    if (!media.playable) {
      throw const FormatException('此地址需要网页解析，不支持直接播放');
    }
    final source = await services.sources.find(next.item.sourceId);
    if (_closed) throw StateError('Playback is closed');
    if (source != null && (!source.enabled || source.suppressed)) {
      throw const FormatException('此源已屏蔽，请选择其他来源');
    }
    var headers =
        next.headersByUri[media.uri] ??
        (next.headers.isNotEmpty
            ? next.headers
            : source == null
            ? <String, String>{}
            : HeaderPolicy.scopedHeaders(
                source.endpoint,
                media.uri,
                source.headers,
              ));
    if (media.requiresResolution) {
      if (source == null) throw const FormatException('解析来源已移除');
      final resolved = await createVodProvider(
        source,
        services.network,
        policy: services.contentPolicy,
      ).resolve(media);
      media = Episode(media.label, resolved.uri);
      headers = resolved.headers;
    }
    if (_closed) throw StateError('Playback is closed');
    resolvedMedia = ResolvedMedia(media.uri, headers: headers);
    final policy = HeaderPolicy({media.uri: headers});
    var hls = media.uri.path.toLowerCase().endsWith('.m3u8');
    if (!hls &&
        !RegExp(
          r'\.(mp4|flv|mkv|webm|ts)$',
          caseSensitive: false,
        ).hasMatch(media.uri.path)) {
      final response = await services.http.open(media.uri, policy: policy);
      final first = await response.body.take(1).toList();
      hls =
          first.isNotEmpty &&
          utf8
              .decode(first.first.take(512).toList(), allowMalformed: true)
              .trimLeft()
              .startsWith('#EXTM3U');
    }
    if (_closed) throw StateError('Playback is closed');
    _gateway = services.gateway.createSession(policy)
      ..normalizeTimestamps =
          !next.live && services.settings.value.contentFilter
      ..selectedQuality = next.quality
      ..filterAds =
          !next.live &&
          (services.settings.value.adFilter ||
              services.settings.value.contentFilter)
      ..cacheEnabled =
          !next.live &&
          (services.settings.value.cache ||
              services.settings.value.contentFilter);
    final sessionGeneration = _generation;
    _gateway!.prefetch.onUnavailable = () {
      if (_closed || blocked || sessionGeneration != _generation) return;
      routeWarning = '连续预缓存失败，后续播放可能中断。是否保留进度切换线路或渠道？';
      notifyListeners();
    };
    _gateway!.prefetch
      ..enabled = services.settings.value.cache && !next.live
      ..window = services.settings.value.prefetchSegments
      ..maxBytes = services.settings.value.episodeCacheMiB * 1024 * 1024
      ..whilePaused = services.settings.value.cacheWhilePaused;
    return _gateway!.register(media.uri, playlist: hls, streaming: !hls);
  }

  void _onState(PlaybackSnapshot next) {
    if (_closed || blocked || _switching || request == null) return;
    final expectedSeek = _expectedSeek;
    if (expectedSeek != null) {
      if ((next.position - expectedSeek).abs() >
          const Duration(milliseconds: 750)) {
        return;
      }
      _expectedSeek = null;
      _seekSettleTimer?.cancel();
      diagnostics.add('播放已确认跳转 ${next.position.inMilliseconds} ms');
    }
    if (next.position + const Duration(seconds: 2) < state.position &&
        expectedSeek == null &&
        !_filterSeeking &&
        _resume == null) {
      _rearmSkips();
      diagnostics.add(
        '非主动时间回退 ${state.position.inMilliseconds} -> ${next.position.inMilliseconds} ms',
      );
    }
    state = next;
    if (_resume != null && next.duration > Duration.zero) {
      final target = _resume!;
      _resume = null;
      unawaited(seek(target < originalDuration ? target : Duration.zero));
      notifyListeners();
      return;
    }
    if (_resume == null) {
      _contentSession?.observe(
        next.position,
        next.duration,
        playing: next.playing,
        buffering: next.buffering,
      );
    }
    if (next.playing && _resume == null) _applyDetected();
    _gateway?.prefetch.playing = next.playing;
    _gateway?.prefetch.kick();
    if (_expectedSeek == null &&
        !isLive &&
        workSkipEnabled &&
        services.settings.value.skip &&
        next.playing) {
      _applySkip();
    }
    if (_expectedSeek == null &&
        next.completed &&
        next.duration > Duration.zero &&
        next.position >= next.duration - const Duration(seconds: 2) &&
        !_advancing &&
        !isLive &&
        services.settings.value.autoplay &&
        request!.offline == null) {
      _advancing = true;
      unawaited(nextEpisode());
    }
    notifyListeners();
  }

  void _applySkip() {
    if (_filterSeeking || _expectedSeek != null) return;
    for (final mark in marks) {
      final difference = (mark.duration - originalDuration).inSeconds.abs();
      if (!mark.enabled || difference > 2 || _skipped.contains(mark.id)) {
        continue;
      }
      if (originalPosition >= mark.start && originalPosition < mark.end) {
        _skipped.add(mark.id);
        _undoPosition = originalPosition;
        notice = '已跳过 ${mark.label}，可撤销';
        _filterSeeking = true;
        final generation = _generation;
        unawaited(
          seek(mark.end, rearmSkips: false)
              .catchError((Object _) {
                if (!_closed && generation == _generation) {
                  _skipped.remove(mark.id);
                  notice = '跳过失败，可手动拖动后重试';
                }
              })
              .whenComplete(() {
                if (generation == _generation) _filterSeeking = false;
              }),
        );
        break;
      }
    }
  }

  void _rearmSkips() {
    _skipped.clear();
    _detected.clear();
    pendingFeature = null;
  }

  Duration? _expectedSeek;
  int _seekRevision = 0;
  Future<void>? _seekQueue;
  Timer? _seekSettleTimer;
  Duration get _filterPosition =>
      _expectedSeek ??
      (_resume == null ? state.position : timeline.toProcessed(_resume!));

  Future<void> _seekEngine(Duration target) {
    final revision = ++_seekRevision;
    final generation = _generation;
    _expectedSeek = target;
    _seekSettleTimer?.cancel();
    pendingFeature = null;
    _contentSession?.seek(target);
    diagnostics.add('请求跳转 ${target.inMilliseconds} ms，撤销旧位置检测');
    Future<void> performSeek() async {
      if (_closed || generation != _generation || revision != _seekRevision) {
        return;
      }
      try {
        await engine.seek(target);
        if (_closed || generation != _generation || revision != _seekRevision) {
          return;
        }
        _onState(engine.snapshot);
        if (_expectedSeek != null) {
          _seekSettleTimer = Timer(const Duration(seconds: 3), () {
            if (_closed ||
                generation != _generation ||
                revision != _seekRevision) {
              return;
            }
            diagnostics.add('跳转未到达目标，检测重新跟随实际播放位置');
            _restoreDetectionPosition();
          });
        }
      } catch (_) {
        if (!_closed &&
            generation == _generation &&
            revision == _seekRevision) {
          _restoreDetectionPosition();
        }
        rethrow;
      }
    }

    final previous = _seekQueue;
    final operation = previous == null
        ? performSeek()
        : previous.catchError((Object _) {}).then((_) => performSeek());
    _seekQueue = operation;
    return operation.whenComplete(() {
      if (identical(_seekQueue, operation)) _seekQueue = null;
    });
  }

  void _restoreDetectionPosition() {
    _expectedSeek = null;
    final actual = engine.snapshot;
    _contentSession?.seek(actual.position);
    _onState(actual);
  }

  Future<void> seek(Duration position, {bool rearmSkips = true}) {
    final target = position < Duration.zero
        ? Duration.zero
        : originalDuration > Duration.zero && position > originalDuration
        ? originalDuration
        : position;
    if (rearmSkips) _rearmSkips();
    final processed = timeline.toProcessed(target);
    return _seekEngine(processed);
  }

  Future<void> _startContentFilter(Uri input, int generation) {
    final operation = _initializeContentFilter(input, generation);
    _filterStarts.add(operation);
    return operation.whenComplete(() => _filterStarts.remove(operation));
  }

  Future<void> _initializeContentFilter(Uri input, int generation) async {
    final epoch = ++_filterEpoch;
    final sourceId = request!.item.sourceId;
    bool current() =>
        !_closed && generation == _generation && epoch == _filterEpoch;
    try {
      final settings = services.settings.value;
      final rules = await services.filterFeatures.applicable(
        sourceId: sourceId,
        seriesKey: featureSeriesKey,
        enabledOnly: true,
      );
      if (!current()) return;
      activeFeatures = List.unmodifiable(rules);
      _originFeatures = rules
          .where((rule) => rule.enabled && rule.originKey == workKey)
          .toList();
      diagnostics.add(
        '加载适用内容特征 ${rules.length} 条，本集 ${_originFeatures.length} 条',
      );
      _applyDetected();
      final session = await services.contentFilter.createBackground(
        input,
        _filterPosition,
        rules: rules,
        keywords: settings.filterKeywords,
        ocr: settings.filterOcr,
        asr: settings.filterAsr,
        skipSeconds: settings.filterSkipSeconds,
        strategy: FilterStrategy.parse(settings.filterStrategy),
        onStatus: (message) {
          if (current()) {
            filterStatus = message;
            diagnostics.add(message);
            notifyListeners();
          }
        },
        onHit: (hit) {
          if (!current() || _expectedSeek != null || _resume != null) return;
          _detected.add(hit);
          _applyDetected();
          notifyListeners();
        },
        onDiagnostic: (message) {
          if (!current()) return;
          filterDiagnostic = message;
          diagnostics.add(message);
          notifyListeners();
        },
      );
      if (!current()) {
        if (session != null) {
          await services.contentFilter.releaseBackground(session);
        }
        return;
      }
      _contentSession = session;
      session?.seek(_filterPosition);
      session?.begin();
      session?.observe(
        _filterPosition,
        state.duration,
        playing: state.playing && _expectedSeek == null && _resume == null,
        buffering: state.buffering,
      );
    } catch (_) {
      if (current()) {
        filterStatus = '检测暂不可用，视频继续播放';
        notifyListeners();
      }
    }
  }

  void _applyDetected() {
    if (_filterSeeking ||
        !state.playing ||
        _closed ||
        blocked ||
        _expectedSeek != null ||
        state.duration <= Duration.zero ||
        _resume != null) {
      return;
    }
    _applyOriginFeatures();
    pendingFeature = null;
    final hit = _detected.at(state.position);
    if (hit == null) return;
    if (hit.requiresConfirmation ||
        services.settings.value.filterStrategy == 'confirm') {
      pendingFeature = hit;
      return;
    }
    pendingFeature = null;
    _skipDetected(hit);
  }

  void confirmFeatureSkip() {
    final hit = pendingFeature;
    pendingFeature = null;
    if (hit != null &&
        !_closed &&
        !busy &&
        !blocked &&
        _expectedSeek == null &&
        state.position >= hit.range.start &&
        state.position < hit.range.end) {
      _skipDetected(hit);
    }
    notifyListeners();
  }

  void ignoreFeatureSkip() {
    final hit = pendingFeature;
    pendingFeature = null;
    if (hit != null) {
      _detected.handle(hit);
    }
    notifyListeners();
  }

  void _skipDetected(FilterDetection hit) {
    if (_filterSeeking) return;
    _detected.handle(hit);
    final end = hit.range.end > state.duration ? state.duration : hit.range.end;
    _undoPosition = originalPosition;
    diagnostics.add(
      '跳过 ${hit.range.start.inMilliseconds} -> ${end.inMilliseconds} ms',
    );
    notice =
        '${hit.reason} · 起点 ${(timeline.toOriginal(hit.range.start).inMilliseconds / 1000).toStringAsFixed(1)} 秒，已跳过，可撤销';
    _filterSeeking = true;
    final generation = _generation;
    unawaited(
      _seekEngine(end)
          .catchError((Object _) {
            if (!_closed && generation == _generation) {
              _detected.retry(hit);
              filterStatus = '自动跳过失败，视频继续播放';
            }
          })
          .whenComplete(() {
            if (generation == _generation) _filterSeeking = false;
          }),
    );
  }

  Future<void> _closeContentFilter() async {
    _filterEpoch++;
    _originFeatures = [];
    activeFeatures = const [];
    pendingFeature = null;
    _detected.clear();
    final session = _contentSession;
    _contentSession = null;
    filterStatus = null;
    filterDiagnostic = null;
    if (session != null) {
      await services.contentFilter.releaseBackground(session);
    }
    // Initializers can still be creating directories when playback changes.
    // Invalidated generations release their sessions before close completes.
    await Future.wait(_filterStarts.toList());
  }

  Future<void> toggle() async {
    if (request != null && !_allowed(request!)) {
      _policyChanged();
      return;
    }
    _recoveryTimer?.cancel();
    _userPaused = state.playing;
    if (notice?.startsWith('正在尝试恢复') ?? false) notice = null;
    await engine.playOrPause();
    await save();
    if (!_userPaused && error != null) _scheduleRecovery();
  }

  Future<void> save() async {
    if (blocked ||
        request == null ||
        isLive ||
        (request!.offline != null &&
            request!.kind != PlaybackMediaKind.local) ||
        _switching) {
      return;
    }
    try {
      await services.history.save(
        request!.item,
        line,
        episode,
        originalPosition,
        originalDuration,
      );
    } catch (_) {
      notice = '进度保存失败，请检查可用空间';
      if (!_closed) notifyListeners();
    }
  }

  Future<void> select(int lineIndex, int episodeIndex, {Duration? position}) {
    final current = request!;
    if (current.offline != null &&
        (lineIndex != current.line || episodeIndex != current.episode)) {
      return Future.error(const FormatException('请从下载页选择其他离线剧集'));
    }
    return open(
      PlaybackRequest(
        request!.item,
        line: lineIndex,
        episode: episodeIndex,
        position: position ?? Duration.zero,
        live: isLive,
        headers: request!.headers,
        headersByUri: request!.headersByUri,
        offline: current.offline,
        quality: current.quality,
        mediaKind: current.mediaKind,
      ),
    );
  }

  Future<void> nextEpisode() async {
    if (isLive && request!.item.lines.length > 1) {
      await select((request!.line + 1) % request!.item.lines.length, 0);
      return;
    }
    if (request!.episode + 1 < line.episodes.length) {
      await select(request!.line, request!.episode + 1);
    }
  }

  Future<void> retry() =>
      select(request!.line, request!.episode, position: originalPosition);
  Future<void> beginSpeed() async {
    if (_previousRate != null) return;
    _previousRate = state.rate;
    await engine.setRate(3);
  }

  Future<void> endSpeed() async {
    final previous = _previousRate;
    _previousRate = null;
    if (previous != null) await engine.setRate(previous);
  }

  void markFeatureStart() {
    markTarget;
    featureStart = originalPosition;
    notifyListeners();
  }

  PlaybackMarkTarget get markTarget {
    if (_closed ||
        busy ||
        blocked ||
        request == null ||
        !request!.supportsMarks ||
        originalDuration <= Duration.zero) {
      throw const FormatException('当前媒体尚未就绪，无法标记');
    }
    return PlaybackMarkTarget(
      generation: _generation,
      workKey: workKey,
      seriesKey: seriesKey,
      sourceId: request!.item.sourceId,
      duration: originalDuration,
    );
  }

  void checkMarkTarget(PlaybackMarkTarget target) {
    if (_closed ||
        busy ||
        blocked ||
        request == null ||
        target.generation != _generation ||
        target.workKey != workKey) {
      throw const FormatException('视频已切换，请关闭窗口后重新标记');
    }
  }

  Future<void> saveEpisodeMark({
    required PlaybackMarkTarget target,
    required Duration start,
    required Duration end,
    required String label,
  }) async {
    checkMarkTarget(target);
    final name = label.trim();
    if (name.isEmpty ||
        name.length > 120 ||
        start < Duration.zero ||
        end <= start ||
        end > target.duration) {
      throw const FormatException('请填写有效名称和本集范围，终点不能超过总时长');
    }
    await services.db.atomic(() async {
      checkMarkTarget(target);
      await services.skips.add(
        target.workKey,
        start,
        end,
        target.duration,
        name,
      );
      await services.skips.setWorkEnabled(target.seriesKey, true);
      checkMarkTarget(target);
    }, tables: const {'skip_marks', 'skip_preferences'});
    checkMarkTarget(target);
    if (!services.settings.value.skip) {
      await services.settings.update({'skip': true});
    }
    checkMarkTarget(target);
    await refreshSkipMarks();
    checkMarkTarget(target);
    featureStart = null;
    diagnostics.add(
      '保存本集区间 ${start.inMilliseconds} -> ${end.inMilliseconds} ms',
    );
    notice = '已保存本集区间；自动跳过已开启';
    if (state.playing) _applySkip();
    notifyListeners();
  }

  Future<void> refreshSkipMarks() async {
    if (_closed || request == null) return;
    final generation = _generation;
    final key = workKey, series = seriesKey;
    final loaded = await services.skips.list(key);
    final enabled = await services.skips.workEnabled(series);
    if (_closed || generation != _generation) return;
    marks = loaded;
    workSkipEnabled = enabled;
    notifyListeners();
  }

  void _applyOriginFeatures() {
    for (final rule in _originFeatures) {
      final start = Duration(
        milliseconds: (rule.originStartMs - rule.beforeMs).clamp(0, 86400000),
      );
      final end = Duration(
        milliseconds: rule.originStartMs + rule.sampleMs + rule.afterMs,
      );
      if (originalPosition < start || originalPosition >= end) continue;
      final range = RemovedInterval(
        timeline.toProcessed(start),
        timeline.toProcessed(end),
      );
      _detected.add(FilterDetection(range, '已应用本集标记：${rule.label}'));
    }
  }

  Future<FeatureRule> captureFeature({
    required Duration from,
    required Duration to,
    required String label,
    required FeatureMode mode,
    required int beforeMs,
    required int afterMs,
    required CancellationToken token,
  }) async {
    final current = request;
    if (current == null || isLive || _closed || busy || blocked) {
      throw const FilterFailure('当前无法采集特征');
    }
    if (_captureToken != null) throw const FilterFailure('正在采集特征');
    _captureToken = token;
    final completed = Completer<void>();
    _captureFinished = completed.future;
    final generation = _generation;
    try {
      final input = _playbackInput;
      if (input == null) throw const FilterFailure('媒体尚未就绪');
      final processedFrom = timeline.toProcessed(from);
      final processedTo = timeline.toProcessed(to);
      if (processedTo - processedFrom != to - from) {
        throw const FilterFailure('样本跨越已删除的片段，请选择连续的声音或画面');
      }
      final rule = await FeatureCapture(services.contentFilter).capture(
        input,
        sourceId: current.item.sourceId,
        originKey: workKey,
        from: processedFrom,
        to: processedTo,
        originStart: from,
        knownDuration: state.duration,
        label: label,
        mode: mode,
        beforeMs: beforeMs,
        afterMs: afterMs,
        token: token,
      );
      token.check();
      if (_closed || generation != _generation) {
        throw const FilterFailure('视频已切换，请重新采集');
      }
      featureStart = null;
      diagnostics.add(
        '特征采集 ${mode.name} ${from.inMilliseconds}-${to.inMilliseconds} ms：'
        '${rule.signatures.length} 个短特征；${rule.captureNote}',
      );
      return rule.copyWith(seriesKey: featureSeriesKey);
    } on FormatException catch (error) {
      diagnostics.add('特征采集 ${mode.name} 失败：${error.message}');
      rethrow;
    } on FilterFailure catch (error) {
      diagnostics.add('特征采集 ${mode.name} 失败：${error.message}');
      rethrow;
    } finally {
      _captureToken = null;
      _captureFinished = null;
      completed.complete();
    }
  }

  Future<void> refreshFeatureRules() async {
    if (busy) await _queue;
    if (_closed) return;
    if (services.settings.value.contentFilter && request != null) {
      if (_gateway != null && !_gateway!.normalizeTimestamps) {
        // A newly saved rule enables filtering. Reopen at the current point
        // so playback and extraction both use the corrected timeline now.
        await changeQuality(request!.quality);
        return;
      }
      await _closeContentFilter();
      if (_playbackInput != null) {
        await _startContentFilter(_playbackInput!, _generation);
      }
    } else {
      await _closeContentFilter();
    }
    notifyListeners();
  }

  Future<void> mark() async {
    markTarget;
    if (markStart == null) {
      markStart = originalPosition;
      notifyListeners();
      return;
    }
    await services.skips.add(
      workKey,
      markStart!,
      originalPosition,
      originalDuration,
      '自定义片段',
    );
    markStart = null;
    marks = await services.skips.list(workKey);
    notifyListeners();
  }

  Future<void> undoSkip() async {
    final target = _undoPosition;
    _undoPosition = null;
    notice = null;
    if (target != null) await seek(target, rearmSkips: false);
    notifyListeners();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    services.contentPolicy.removeListener(_policyChanged);
    _closed = true;
    _generation++;
    _captureToken?.cancel();
    _contentSession?.cancel();
    _shutdown.complete();
    cancelRecovery();
    _previousRate = null;
    _saveTimer.cancel();
    _seekSettleTimer?.cancel();
    await save();
    _routeToken.cancel();
    await _states.cancel();
    _captureToken?.cancel();
    await _errors.cancel();
    await _queue;
    await _closeContentFilter();
    await _captureFinished;
    await _seekQueue?.catchError((Object _) {});
    _gateway?.close();
    request?.offline?.close();
    try {
      await engine.dispose();
    } finally {
      dispose();
    }
  }

  void cancelRecovery() {
    _recoveryCancelled = true;
    _recoveryTimer?.cancel();
    if (notice?.startsWith('正在尝试恢复') ?? false) notice = null;
  }

  void _scheduleRecovery() {
    if (_closed ||
        _recoveryCancelled ||
        blocked ||
        _userPaused ||
        _recoveryAttempts >= 2 ||
        request == null ||
        request!.offline != null ||
        recovering) {
      return;
    }
    final generation = _generation;
    _recoveryAttempts++;
    notice = '正在尝试恢复（$_recoveryAttempts / 2），可停止';
    _recoveryTimer = Timer(
      Duration(seconds: _recoveryAttempts),
      () => unawaited(_recover(generation)),
    );
  }

  bool _recoveryIsCurrent(int generation) =>
      !_closed &&
      generation == _generation &&
      !_recoveryCancelled &&
      !_userPaused;

  Future<void> _recover(int generation) async {
    final current = request!;
    final saved = _resume ?? originalPosition;
    final previousLine = line.name;
    final previousEpisode = episode.label;
    try {
      if (isLive) {
        final alternate = (current.episode + 1) % line.episodes.length;
        if (!_recoveryIsCurrent(generation)) return;
        await open(
          PlaybackRequest(
            current.item,
            line: current.line,
            episode: alternate,
            live: true,
            headers: current.headers,
            headersByUri: current.headersByUri,
            quality: current.quality,
          ),
          automatic: true,
        );
      } else {
        final source = await services.sources.find(current.item.sourceId);
        if (source == null || !source.enabled || source.suppressed) {
          cancelRecovery();
          if (!_closed) notifyListeners();
          return;
        }
        final updated = await services.detail(
          current.item.sourceId,
          current.item.id,
        );
        if (!_recoveryIsCurrent(generation)) return;
        var lineIndex = updated.lines.indexWhere((l) => l.name == previousLine);
        if (_recoveryAttempts == 2 && updated.lines.length > 1) {
          await switchAlternativeLine(refreshed: updated);
          return;
        }
        if (lineIndex < 0) throw StateError('播放线路已变化');
        final matches = matchingEpisodes(
          previousEpisode,
          updated.lines[lineIndex].episodes,
        );
        if (matches.length != 1) throw StateError('剧集无法唯一匹配');
        if (!_recoveryIsCurrent(generation)) return;
        await open(
          PlaybackRequest(
            updated,
            line: lineIndex,
            episode: matches.single,
            position: saved,
            headers: current.headers,
            headersByUri: current.headersByUri,
            quality: current.quality,
          ),
          automatic: true,
        );
      }
    } catch (_) {
      if (!_closed && generation == _generation) {
        error = '自动恢复失败，请选择其他线路或来源';
        _scheduleRecovery();
        notifyListeners();
      }
    }
  }
}
