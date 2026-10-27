import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../app/app_services.dart';
import '../../../core/network/header_policy.dart';
import '../../../media/gateway/media_gateway.dart';
import '../../../media/gateway/offline_server.dart';
import '../../../media/hls/timeline.dart';
import '../../../media/hls/hls_quality.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/domain/vod_provider.dart';
import '../../catalog/data/provider_factory.dart';
import '../../../core/network/document_client.dart';
import '../data/skip_repository.dart';
import '../domain/player_engine.dart';

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
}

final class PlaybackController extends ChangeNotifier {
  PlaybackController(this.services, this.engine) {
    _states = engine.states.listen(_onState);
    _errors = engine.errors.listen((_) {
      if (!_switching && !_closed) {
        error = '播放中断。可重试、切换线路或重新搜索其他来源';
        _scheduleRecovery();
        notifyListeners();
      }
    });
    _saveTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(save()),
    );
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
  Future<void> _queue = Future.value();
  bool _switching = false;
  bool _closed = false;
  bool _advancing = false;
  int _generation = 0;
  Duration? _resume;
  String? error;
  String? notice;
  List<SkipMark> marks = [];
  Duration? markStart;
  Duration? _undoPosition;
  final _skipped = <String>{};
  double? _previousRate;
  Timer? _recoveryTimer;
  int _recoveryAttempts = 0;
  bool _recoveryCancelled = false;
  bool workSkipEnabled = true;
  String get seriesKey => '${request!.item.sourceId}|${request!.item.id}';
  bool get recovering => _recoveryTimer?.isActive ?? false;
  bool get canUndoSkip => _undoPosition != null;
  bool get canCancelRecovery =>
      !_recoveryCancelled && (notice?.startsWith('正在尝试恢复') ?? false);
  MediaTimeline get timeline => _gateway?.timeline ?? const MediaTimeline([]);
  Duration get originalPosition => timeline.toOriginal(state.position);
  Duration get originalDuration => timeline.toOriginal(state.duration);
  PlayLine get line => request!.item.lines[request!.line];
  Episode get episode => line.episodes[request!.episode];
  String get workKey =>
      '${request!.item.sourceId}|${request!.item.id}|${line.name}|${episode.label}';
  List<HlsQuality> get qualities => _gateway?.qualities ?? const [];
  Future<void> changeQuality(Uri? quality) async {
    final current = request;
    if (current == null || busy || current.offline != null) return;
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
    await engine.setRate(rate);
    if (!playing) await engine.pause();
  }

  bool get busy => _switching;
  bool get isLive => request?.live ?? false;

  Future<void> open(PlaybackRequest next, {bool automatic = false}) {
    _recoveryTimer?.cancel();
    if (!automatic) {
      _recoveryAttempts = 0;
      _recoveryCancelled = false;
    }
    final generation = ++_generation;
    _queue = _queue.catchError((Object _) {}).then((_) async {
      if (_closed || generation != _generation) return;
      await _open(next, generation);
    });
    return _queue;
  }

  Future<void> _open(PlaybackRequest next, int generation) async {
    await save();
    _switching = true;
    error = null;
    notifyListeners();
    try {
      await engine.stop();
      _gateway?.close();
      if (request?.offline != next.offline) request?.offline?.close();
      request = next;
      resolvedMedia = null;
      state = const PlaybackSnapshot();
      markStart = null;
      _undoPosition = null;
      notice = null;
      _skipped.clear();
      _resume = next.position > Duration.zero ? next.position : null;
      _advancing = false;
      marks = next.live || next.offline != null
          ? []
          : await services.skips.list(workKey);
      workSkipEnabled = await services.skips.workEnabled(seriesKey);
      final uri = next.offline?.uri ?? await _onlineUri(next);
      if (generation != _generation || _closed) return;
      await engine.open(uri);
      _switching = false;
      _onState(engine.snapshot);
    } catch (e) {
      error = e is RemoteFailure
          ? e.message
          : e is FormatException
          ? e.message
          : '无法打开媒体。请检查来源，或切换线路后重试';
    } finally {
      _switching = false;
      if (error != null) _scheduleRecovery();
      if (!_closed) notifyListeners();
    }
  }

  Future<Uri> _onlineUri(PlaybackRequest next) async {
    var media = episode;
    if (!media.playable) {
      throw const FormatException('此地址需要网页解析，不支持直接播放');
    }
    final source = await services.sources.find(next.item.sourceId);
    if (source != null && (!source.enabled || source.suppressed)) {
      throw const FormatException('此源已屏蔽，请选择其他来源');
    }
    var headers =
        next.headersByUri[media.uri] ??
        (next.headers.isNotEmpty
            ? next.headers
            : source?.headers ?? <String, String>{});
    if (media.requiresResolution) {
      if (source == null) throw const FormatException('解析来源已移除');
      final resolved = await createVodProvider(
        source,
        services.network,
      ).resolve(media);
      media = Episode(media.label, resolved.uri);
      headers = resolved.headers;
    }
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
    _gateway = services.gateway.createSession(policy)
      ..selectedQuality = next.quality
      ..filterAds = services.settings.value.adFilter && !next.live
      ..cacheEnabled = services.settings.value.cache && !next.live;
    _gateway!.prefetch
      ..enabled = services.settings.value.cache && !next.live
      ..window = services.settings.value.prefetchSegments
      ..maxBytes = services.settings.value.episodeCacheMiB * 1024 * 1024
      ..whilePaused = services.settings.value.cacheWhilePaused;
    return _gateway!.register(media.uri, playlist: hls, streaming: !hls);
  }

  void _onState(PlaybackSnapshot next) {
    if (_closed || _switching || request == null) return;
    state = next;
    _gateway?.prefetch.playing = next.playing;
    _gateway?.prefetch.kick();
    if (_resume != null && next.duration > Duration.zero) {
      final target = _resume!;
      _resume = null;
      unawaited(seek(target < originalDuration ? target : Duration.zero));
    } else if (!isLive &&
        workSkipEnabled &&
        services.settings.value.skip &&
        next.playing) {
      _applySkip();
    }
    if (next.completed &&
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
    for (final mark in marks) {
      final difference = (mark.duration - originalDuration).inSeconds.abs();
      if (!mark.enabled || difference > 2 || _skipped.contains(mark.id)) {
        continue;
      }
      if (originalPosition >= mark.start && originalPosition < mark.end) {
        _skipped.add(mark.id);
        _undoPosition = originalPosition;
        notice = '已跳过 ${mark.label}，可撤销';
        unawaited(seek(mark.end));
        break;
      }
    }
  }

  Future<void> seek(Duration position) => engine.seek(
    timeline.toProcessed(
      Duration(
        milliseconds: position.inMilliseconds.clamp(
          0,
          originalDuration.inMilliseconds,
        ),
      ),
    ),
  );
  Future<void> toggle() async {
    cancelRecovery();
    await engine.playOrPause();
    await save();
  }

  Future<void> save() async {
    if (request == null || isLive || request!.offline != null || _switching) {
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
    }
  }

  Future<void> select(int lineIndex, int episodeIndex, {Duration? position}) =>
      open(
        PlaybackRequest(
          request!.item,
          line: lineIndex,
          episode: episodeIndex,
          position: position ?? Duration.zero,
          live: isLive,
          headers: request!.headers,
          headersByUri: request!.headersByUri,
        ),
      );
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

  Future<void> mark() async {
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
    if (target != null) await seek(target);
    notifyListeners();
  }

  Future<void> close() async {
    cancelRecovery();
    await endSpeed();
    await save();
    _closed = true;
    _generation++;
    _saveTimer.cancel();
    await _states.cancel();
    await _errors.cancel();
    await _queue;
    await engine.dispose();
    _gateway?.close();
    request?.offline?.close();
    dispose();
  }

  void cancelRecovery() {
    _recoveryCancelled = true;
    _recoveryTimer?.cancel();
    if (notice?.startsWith('正在尝试恢复') ?? false) notice = null;
  }

  void _scheduleRecovery() {
    if (_closed ||
        _recoveryCancelled ||
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

  Future<void> _recover(int generation) async {
    final current = request!;
    final saved = originalPosition;
    final previousLine = line.name;
    final previousEpisode = episode.label;
    try {
      if (isLive) {
        final alternate = (current.episode + 1) % line.episodes.length;
        if (_closed || generation != _generation || _recoveryCancelled) return;
        await open(
          PlaybackRequest(
            current.item,
            line: current.line,
            episode: alternate,
            live: true,
            headers: current.headers,
            headersByUri: current.headersByUri,
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
        if (_closed || generation != _generation || _recoveryCancelled) return;
        var lineIndex = updated.lines.indexWhere((l) => l.name == previousLine);
        if (_recoveryAttempts == 2 && updated.lines.length > 1) {
          lineIndex = (lineIndex + 1) % updated.lines.length;
        }
        if (lineIndex < 0) throw StateError('播放线路已变化');
        final matches = matchingEpisodes(
          previousEpisode,
          updated.lines[lineIndex].episodes,
        );
        if (matches.length != 1) throw StateError('剧集无法唯一匹配');
        if (_closed || generation != _generation || _recoveryCancelled) return;
        await open(
          PlaybackRequest(
            updated,
            line: lineIndex,
            episode: matches.single,
            position: saved,
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
