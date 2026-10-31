import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../media/network/media_probe.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/data/provider_factory.dart';
import '../../sources/domain/video_source.dart';
import '../application/line_recommendation.dart';

/// Probes only the selected provider's lines for this movie and episode.
final class LineSelector extends StatefulWidget {
  const LineSelector({
    super.key,
    required this.services,
    required this.item,
    required this.selected,
    required this.onSelected,
    this.autoSelect = false,
    this.episodeLabel = '',
    this.headers = const {},
    this.headersByUri = const {},
  });
  final bool autoSelect;
  final AppServices services;
  final CatalogItem item;
  final int selected;
  final String episodeLabel;
  final Map<String, String> headers;
  final Map<Uri, Map<String, String>> headersByUri;
  final ValueChanged<int> onSelected;
  @override
  State<LineSelector> createState() => _LineSelectorState();
}

final class _LineSelectorState extends State<LineSelector> {
  final _status = <int, String>{};
  final _responses = <int, ProbeResult>{};
  bool _manual = false;
  var _token = CancellationToken();
  int _generation = 0;
  String? _sourceName;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant LineSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item ||
        oldWidget.services != widget.services ||
        oldWidget.episodeLabel != widget.episodeLabel ||
        !mapEquals(oldWidget.headers, widget.headers) ||
        !mapEquals(oldWidget.headersByUri, widget.headersByUri)) {
      _restart();
    }
  }

  void _restart() {
    _token.cancel();
    _token = CancellationToken();
    _generation++;
    _status.clear();
    _responses.clear();
    _sourceName = null;
    _manual = false;
    // Live CatalogItem lines represent channels, not VOD provider lines.
    if (widget.item.sourceId != 'live') {
      unawaited(_run(widget, _token, _generation));
    }
  }

  bool _current(int generation) =>
      mounted && generation == _generation && !_token.isCancelled;

  Future<void> _run(
    LineSelector scope,
    CancellationToken token,
    int generation,
  ) async {
    try {
      final source = await scope.services.sources.find(scope.item.sourceId);
      if (!_current(generation)) return;
      if (source == null || !source.available) {
        throw const FormatException('当前渠道不可用，请返回选择渠道');
      }
      setState(() => _sourceName = source.displayName);
      var cursor = 0;
      Future<void> worker() async {
        while (_current(generation) && cursor < scope.item.lines.length) {
          await _check(cursor++, scope, source, token, generation);
        }
      }

      final concurrency = scope.services.settings.value.lineProbeConcurrency;
      await Future.wait([
        for (var i = 0; i < scope.item.lines.length && i < concurrency; i++)
          worker(),
      ]);
      if (_current(generation) &&
          scope.autoSelect &&
          !_manual &&
          _responses.isNotEmpty) {
        final ranked = _responses.keys.toList()
          ..sort(
            (a, b) => compareLineResponses(_responses[a]!, _responses[b]!),
          );
        widget.onSelected(ranked.first);
      }
    } catch (error) {
      if (!_current(generation)) return;
      setState(() {
        for (var i = 0; i < scope.item.lines.length; i++) {
          _status.putIfAbsent(
            i,
            () => error is FormatException ? error.message : '检测未完成',
          );
        }
      });
    }
  }

  Future<void> _check(
    int index,
    LineSelector scope,
    VideoSource source,
    CancellationToken token,
    int generation,
  ) async {
    if (!scope.services.contentPolicy.itemAllowed(scope.item)) {
      setState(() => _status[index] = '已屏蔽');
      return;
    }
    final episodes = scope.item.lines[index].episodes;
    if (episodes.isEmpty) {
      setState(() => _status[index] = '无剧集');
      return;
    }
    final matches = matchingEpisodes(scope.episodeLabel, episodes);
    if (scope.episodeLabel.isNotEmpty && matches.length != 1) {
      setState(() => _status[index] = '没有唯一匹配的剧集');
      return;
    }
    final episode = matches.length == 1
        ? episodes[matches.single]
        : episodes.first;
    setState(() => _status[index] = '检测中');
    try {
      if (!episode.playable) throw const FormatException('此地址无法直接播放');
      var uri = episode.uri;
      var effectiveHeaders =
          scope.headersByUri[uri] ??
          (scope.headers.isEmpty
              ? HeaderPolicy.scopedHeaders(source.endpoint, uri, source.headers)
              : scope.headers);
      if (episode.requiresResolution) {
        final media = await createVodProvider(
          source,
          scope.services.network,
          cancellation: token,
          policy: scope.services.contentPolicy,
        ).resolve(episode);
        uri = media.uri;
        effectiveHeaders = media.headers;
      }
      token.check();
      final result = await probeMedia(
        scope.services.http,
        uri,
        HeaderPolicy({uri: effectiveHeaders}),
        token,
        maxBytes: 256 * 1024,
        availabilityOnly: true,
      );
      if (!_current(generation)) return;
      setState(() {
        _responses[index] = result;
        _status[index] =
            '${result.firstByte.inMilliseconds} ms · ${result.resolution == null ? '画质未知' : '清单声明 ${result.resolution}'}';
      });
    } catch (error) {
      if (!_current(generation)) return;
      setState(
        () => _status[index] = switch (error) {
          TimeoutException() => '检测超时，仍可播放尝试',
          FormatException() => error.message,
          ProbeInconclusive() => error.message,
          SocketException() => '连接失败，可重试播放',
          _ => '检测未完成，可尝试播放',
        },
      );
    }
  }

  Future<void> _select(int index) async {
    final generation = _generation;
    if (widget.item.sourceId != 'live' && !_responses.containsKey(index)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('线路尚未验证可用'),
          content: Text('${_status[index] ?? '等待检测'}。是否仍选择此线路？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('仍然选择'),
            ),
          ],
        ),
      );
      if (confirmed != true || !_current(generation)) return;
    }
    if (!_current(generation)) return;
    _manual = true;
    widget.onSelected(index);
  }

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.item.sourceId == 'live';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          live
              ? '直播频道'
              : '当前渠道：${_sourceName ?? '加载中'} · 本片 ${widget.item.lines.length} 条播放线路',
        ),
        if (!live)
          const Text(
            '仅检测本片线路 · 每路最多 256 KiB / 20 秒网络时间（不含排队），收到媒体数据即结束；不保证完整播放',
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < widget.item.lines.length; i++)
              ChoiceChip(
                label: Text(
                  live
                      ? widget.item.lines[i].name
                      : '线路 ${i + 1}：${widget.item.lines[i].name} · ${_status[i] ?? '等待检测'}',
                ),
                selected: widget.selected == i,
                onSelected: (_) => _select(i),
              ),
          ],
        ),
      ],
    );
  }
}
