import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../media/network/media_probe.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/data/provider_factory.dart';

/// A bounded probe queue owned by the currently visible line selector.
final class LineSelector extends StatefulWidget {
  const LineSelector({
    super.key,
    required this.services,
    required this.item,
    required this.selected,
    required this.onSelected,
    this.episodeLabel = '',
    this.headers = const {},
    this.headersByUri = const {},
  });
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
  final _token = CancellationToken();
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final source = await widget.services.sources.find(widget.item.sourceId);
      if (!mounted) return;
      var cursor = 0;
      Future<void> worker() async {
        while (!_token.isCancelled && cursor < widget.item.lines.length) {
          await _check(cursor++, source?.headers ?? {});
        }
      }

      await Future.wait(List.generate(2, (_) => worker()));
    } catch (_) {
      if (mounted) {
        setState(() {
          for (var i = 0; i < widget.item.lines.length; i++) {
            _status.putIfAbsent(i, () => '检测未完成');
          }
        });
      }
    }
  }

  Future<void> _check(int index, Map<String, String> headers) async {
    final episodes = widget.item.lines[index].episodes;
    if (episodes.isEmpty) {
      if (mounted) setState(() => _status[index] = '无剧集');
      return;
    }
    final matches = matchingEpisodes(widget.episodeLabel, episodes);
    final episode = matches.length == 1
        ? episodes[matches.single]
        : episodes.first;
    final token = CancellationToken();
    final remove = _token.listen(token.cancel);
    if (mounted) setState(() => _status[index] = '检测中');
    try {
      var uri = episode.uri;
      var effectiveHeaders =
          widget.headersByUri[uri] ??
          (widget.headers.isEmpty ? headers : widget.headers);
      if (episode.requiresResolution) {
        final source = await widget.services.sources.find(widget.item.sourceId);
        if (source == null) throw const FormatException('解析来源已移除');
        final media = await createVodProvider(
          source,
          widget.services.network,
          cancellation: token,
        ).resolve(episode);
        uri = media.uri;
        effectiveHeaders = media.headers;
      }
      final result = await probeMedia(
        widget.services.http,
        uri,
        HeaderPolicy({uri: effectiveHeaders}),
        token,
        maxBytes: 256 * 1024,
        availabilityOnly: true,
      );
      token.check();
      if (mounted) {
        setState(
          () => _status[index] = '${result.firstByte.inMilliseconds} ms · 媒体响应',
        );
      }
    } catch (error) {
      if (mounted && !_token.isCancelled) {
        setState(
          () => _status[index] = switch (error) {
            TimeoutException() => '检测超时，仍可播放尝试',
            FormatException() => error.message,
            SocketException() => '连接失败，可重试播放',
            _ => '检测未完成，可尝试播放',
          },
        );
      }
    } finally {
      remove();
    }
  }

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('线路响应检测 · 每路最多 256 KiB / 20 秒网络时间（不含排队），收到媒体数据即结束；不保证完整播放'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < widget.item.lines.length; i++)
            ChoiceChip(
              label: Text(
                '${widget.item.lines[i].name} · ${_status[i] ?? '等待检测'}',
              ),
              selected: widget.selected == i,
              onSelected: (_) => widget.onSelected(i),
            ),
        ],
      ),
    ],
  );
}
