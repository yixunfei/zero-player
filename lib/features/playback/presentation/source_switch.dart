import 'package:flutter/material.dart' hide SearchController;
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../search/application/search_controller.dart';
import '../application/playback_controller.dart';
import '../../catalog/presentation/source_choices.dart';
import '../../sources/presentation/block_source_button.dart';

Future<void> switchPlaybackSource(
  BuildContext context,
  AppServices services,
  PlaybackController player,
) => perform(context, () async {
  final request = player.request;
  if (request == null) return;
  final currentSource = await services.sources.find(request.item.sourceId);
  if (!context.mounted) return;
  final position = player.originalPosition;
  final label = player.episode.label;
  final search = SearchController(
    services.sources,
    services.network,
    services.history,
  );
  final work = search.search(
    request.item.title,
    filterAdult: services.settings.value.filterAdult,
    concurrency: services.settings.value.searchConcurrency,
  );
  CatalogItem? selected;
  try {
    selected = await showDialog<CatalogItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择来源与版本'),
        content: _sourceChoices(
          context,
          services,
          search,
          currentSource?.displayName ?? '当前来源',
          currentSource?.description ?? '',
          request.item.sourceId,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  } finally {
    search.cancel();
    await work;
    search.dispose();
  }
  if (selected == null) return;
  final detail = await services.detail(selected.sourceId, selected.id);
  if (!context.mounted) return;
  final matches = <(int, int)>[];
  for (var i = 0; i < detail.lines.length; i++) {
    for (final j in matchingEpisodes(label, detail.lines[i].episodes)) {
      matches.add((i, j));
    }
  }
  final choice = await _chooseEpisode(
    context,
    detail,
    matches,
    label,
    position,
  );
  if (choice != null) {
    await player.open(
      PlaybackRequest(
        detail,
        line: choice.$1,
        episode: choice.$2,
        position: matches.contains(choice) ? position : Duration.zero,
      ),
    );
  }
});

Widget _sourceChoices(
  BuildContext context,
  AppServices services,
  SearchController search,
  String name,
  String description,
  String currentId,
) => SizedBox(
  width: 600,
  height: 400,
  child: ListenableBuilder(
    listenable: search,
    builder: (context, _) => ListView(
      children: [
        ListTile(
          title: Text('当前来源 · $name'),
          subtitle: Text(description),
          trailing: search.statuses[currentId] == '已屏蔽'
              ? const Text('已屏蔽')
              : BlockSourceButton(
                  name: name,
                  onBlock: () => search.blockSource(currentId),
                ),
        ),
        if (search.loading) const LinearProgressIndicator(),
        Text(search.error ?? '屏蔽后不再参与搜索、自动换源与后续下载，可在源管理中重新启用。'),
        SourceChoices(
          services: services,
          items: List.of(search.items),
          onSelected: (item) => Navigator.pop(context, item),
          onBlock: search.blockSource,
        ),
        for (final id in search.failedSources)
          ListTile(
            title: Text(search.sourceNames[id] ?? id),
            subtitle: Text(search.statuses[id] ?? ''),
            trailing: BlockSourceButton(
              name: search.sourceNames[id] ?? '此来源',
              onBlock: () => search.blockSource(id),
            ),
          ),
      ],
    ),
  ),
);

Future<(int, int)?> _chooseEpisode(
  BuildContext context,
  CatalogItem detail,
  List<(int, int)> matches,
  String label,
  Duration position,
) async {
  return await showDialog<(int, int)>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(
        matches.isEmpty
            ? '没有匹配的剧集，请手动选择'
            : '确认续播 $label · ${clockText(position)}',
      ),
      children: [
        if (matches.isNotEmpty)
          for (final pair in matches)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, pair),
              child: Text(
                '${detail.lines[pair.$1].name} · ${detail.lines[pair.$1].episodes[pair.$2].label}',
              ),
            ),
        if (matches.isEmpty)
          for (var i = 0; i < detail.lines.length; i++)
            for (var j = 0; j < detail.lines[i].episodes.length; j++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (i, j)),
                child: Text(
                  '${detail.lines[i].name} · ${detail.lines[i].episodes[j].label}',
                ),
              ),
      ],
    ),
  );
}
