import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../playback/application/playback_controller.dart';
import '../../downloads/presentation/download_selection.dart';
import '../domain/catalog_item.dart';
import 'movie_header.dart';
import '../../playback/presentation/line_selector.dart';
import '../../sources/presentation/block_source_button.dart';
import '../../sources/presentation/channel_favorite_action.dart';

final class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.services,
    required this.sourceId,
    required this.remoteId,
  });
  final AppServices services;
  final String sourceId;
  final String remoteId;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

final class _DetailPageState extends State<DetailPage> {
  late Future<CatalogItem> _future;
  int selectedLine = 0;
  @override
  void initState() {
    super.initState();
    _load();
    widget.services.contentPolicy.addListener(_policyChanged);
  }

  void _policyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.services.contentPolicy.removeListener(_policyChanged);
    super.dispose();
  }

  void _load() {
    widget.services.searchSourceId = widget.sourceId;
    _future = widget.services.detail(widget.sourceId, widget.remoteId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('影片详情')),
    body: SafeArea(
      child: LoadView(
        future: _future,
        retry: () => setState(_load),
        errorAction: BlockSourceButton(
          name: '当前来源',
          onBlock: () =>
              widget.services.sources.setEnabled(widget.sourceId, false),
        ),
        builder: (item) => widget.services.contentPolicy.itemAllowed(item)
            ? _content(item)
            : const EmptyState('内容已屏蔽', '当前成人过滤或监管规则不允许访问此内容'),
      ),
    ),
  );

  Widget _content(CatalogItem item) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      MovieHeader(item: item),
      const SizedBox(height: 20),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          ChannelFavoriteAction(
            sourceId: item.sourceId,
            repository: widget.services.sources,
          ),
          FilledButton.icon(
            onPressed: item.lines.isEmpty ? null : () => _resume(item),
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放 / 继续观看'),
          ),
          OutlinedButton.icon(
            onPressed: item.lines.isEmpty
                ? null
                : () => selectDownloads(
                    context,
                    widget.services,
                    item,
                    selectedLine,
                  ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载选集'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.push(
              Uri(
                path: '/search',
                queryParameters: {'q': item.title, 'source': item.sourceId},
              ).toString(),
            ),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('查找其他来源'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      if (item.lines.isEmpty) const Text('此来源没有可用的播放线路，请尝试其他来源'),
      LineSelector(
        key: ValueKey('${item.sourceId}/${item.id}'),
        services: widget.services,
        item: item,
        selected: selectedLine,
        onSelected: (i) => setState(() => selectedLine = i),
      ),
      if (item.lines.isNotEmpty) ...[
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < item.lines[selectedLine].episodes.length; i++)
              OutlinedButton(
                onPressed: () => _play(item, selectedLine, i),
                child: Text(item.lines[selectedLine].episodes[i].label),
              ),
          ],
        ),
      ],
    ],
  );

  void _play(
    CatalogItem item,
    int line,
    int episode, {
    Duration position = Duration.zero,
  }) => context.push(
    '/player',
    extra: PlaybackRequest(
      item,
      line: line,
      episode: episode,
      position: position,
    ),
  );
  Future<void> _resume(CatalogItem item) => perform(context, () async {
    final entry = await widget.services.history.latest(item.sourceId, item.id);
    if (!mounted) return;
    if (entry != null) {
      final lineIndex = item.lines.indexWhere(
        (line) => line.name == entry.line,
      );
      if (lineIndex >= 0) {
        final matches = matchingEpisodes(
          entry.episode,
          item.lines[lineIndex].episodes,
        );
        if (matches.length == 1) {
          _play(item, lineIndex, matches.single, position: entry.position);
          return;
        }
      }
      message(context, '上次的线路或剧集已变化，请重新选择剧集');
      return;
    }
    _play(item, selectedLine, 0);
  });
}
