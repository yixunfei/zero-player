import 'package:flutter/material.dart' hide SearchController;
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../search/application/search_controller.dart';
import '../application/playback_controller.dart';
import '../../catalog/presentation/source_choices.dart';
import '../../catalog/presentation/source_choices_dialog.dart';
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
  final position =
      player.request!.position > player.originalPosition && player.error != null
      ? player.request!.position
      : player.originalPosition;
  final label = player.episode.label;
  final search = SearchController(
    services.sources,
    services.network,
    services.history,
  );
  final work = search.search(
    request.item.title,
    preferredSourceId: request.item.sourceId,
    filterAdult: services.settings.value.filterAdult,
    concurrency: services.settings.value.searchConcurrency,
  );
  CatalogItem? selected;
  try {
    selected = await showDialog<CatalogItem>(
      context: context,
      builder: (context) => SourceChoicesDialog(
        title: '选择来源与版本',
        child: _sourceChoices(
          context,
          services,
          search,
          currentSource?.displayName ?? '当前来源',
          currentSource?.description ?? '',
          request.item.sourceId,
        ),
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
    if (player.request != request || !context.mounted) return;
    final playing = !player.userPaused;
    final rate = player.state.rate;
    await player.open(
      PlaybackRequest(
        detail,
        line: choice.$1,
        episode: choice.$2,
        position: matches.contains(choice)
            ? player.error != null && player.originalPosition == Duration.zero
                  ? position
                  : player.originalPosition
            : Duration.zero,
      ),
    );
    if (context.mounted &&
        player.request?.item == detail &&
        player.error == null) {
      await player.engine.setRate(rate);
      if (!playing) await player.engine.pause();
    }
  }
});

Widget _sourceChoices(
  BuildContext context,
  AppServices services,
  SearchController search,
  String name,
  String description,
  String currentId,
) => ListenableBuilder(
  listenable: search,
  builder: (context, _) => ListView(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(
          '当前来源 · $name',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: search.statuses[currentId] == '已屏蔽'
            ? const Text('已屏蔽')
            : BlockSourceButton(
                name: name,
                compact: MediaQuery.sizeOf(context).shortestSide < 600,
                onBlock: () => search.blockSource(currentId),
              ),
      ),
      if (search.loading) const LinearProgressIndicator(),
      Text(
        search.error ?? '屏蔽后不再参与搜索、自动换源与后续下载，可在源管理中重新启用。',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      SourceChoices(
        services: services,
        items: search.groups.values.expand((group) => group).toList(),
        sourceNames: search.sourceNames,
        sourceLabels: search.sourceLabels,
        onSelected: (item) => Navigator.pop(context, item),
        onBlock: search.blockSource,
      ),
      for (final id in search.failedSources)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            search.sourceNames[id] ?? id,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            search.statuses[id] ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: BlockSourceButton(
            name: search.sourceNames[id] ?? '此来源',
            compact: MediaQuery.sizeOf(context).shortestSide < 600,
            onBlock: () => search.blockSource(id),
          ),
        ),
    ],
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
