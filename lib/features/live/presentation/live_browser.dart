import 'package:flutter/material.dart';
import '../../../app/list_keyboard_navigation.dart';
import 'live_channel_tile.dart';
import '../domain/live_channel.dart';
import '../domain/channel_order.dart';

/// Adaptive television guide: groups, channels and a focused-channel panel.
final class LiveBrowser extends StatelessWidget {
  const LiveBrowser({
    super.key,
    required this.channels,
    required this.group,
    required this.query,
    required this.controller,
    required this.onGroup,
    required this.onSelect,
    required this.onPlay,
    required this.onFavorite,
    required this.onToggle,
    required this.onEpg,
    required this.onProbe,
    this.selectedId,
  });
  final List<LiveChannel> channels;
  final String group, query;
  final String? selectedId;
  final ScrollController controller;
  final ValueChanged<String> onGroup, onSelect;
  final ValueChanged<LiveChannel> onPlay, onFavorite, onToggle, onEpg, onProbe;

  @override
  Widget build(BuildContext context) {
    final shown = channels
        .where((c) => matchesChannel(c, group, query))
        .toList();
    if (group == '最近') {
      shown.sort(
        (a, b) => (b.watchedAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.watchedAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    }
    final selected =
        shown.where((c) => c.id == selectedId).firstOrNull ?? shown.firstOrNull;
    final extra = channels.map(channelGroup).toSet()
      ..removeAll({'央视', '卫视', '收藏', '最近', '全部', '待处理', '已停用', '已移除'});
    final groups = [
      '央视',
      '卫视',
      '收藏',
      '最近',
      '全部',
      '待处理',
      '已停用',
      '已移除',
      ...(extra.toList()..sort()),
    ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 1000 && bounds.maxHeight >= 450;
        final horizontal = bounds.maxWidth < 700 || bounds.maxHeight < 450;
        return Column(
          children: [
            if (horizontal) _horizontalGroups(groups),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!horizontal) _verticalGroups(context, groups),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            '$group · ${shown.length} 个频道 · 方向键选择，确认播放',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (!wide && selected != null)
                          _compactPreview(context, selected),
                        Expanded(child: _channels(context, shown, selected)),
                      ],
                    ),
                  ),
                  if (wide && selected != null)
                    SizedBox(width: 320, child: _preview(context, selected)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _horizontalGroups(List<String> groups) => SizedBox(
    height: 56,
    child: ListView(
      primary: false,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final name in groups)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(name),
              selected: group == name,
              onSelected: (_) => onGroup(name),
            ),
          ),
      ],
    ),
  );

  Widget _verticalGroups(BuildContext context, List<String> groups) => SizedBox(
    width: 150,
    child: ListView(
      primary: false,
      padding: const EdgeInsets.all(8),
      children: [
        for (final name in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              selected: group == name,
              selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(name),
              onTap: () => onGroup(name),
            ),
          ),
      ],
    ),
  );

  Widget _channels(
    BuildContext context,
    List<LiveChannel> shown,
    LiveChannel? selected,
  ) {
    if (shown.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('当前分组暂无频道，试试全部、已停用或刷新订阅'),
        ),
      );
    }
    return ListKeyboardNavigation(
      controller: controller,
      child: Scrollbar(
        controller: controller,
        child: ListView.builder(
          key: const ValueKey('live-channel-list'),
          controller: controller,
          padding: const EdgeInsets.all(8),
          itemCount: shown.length,
          itemBuilder: (_, index) =>
              _tile(context, shown[index], selected?.id == shown[index].id),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, LiveChannel channel, bool selected) =>
      LiveChannelTile(
        key: ValueKey(channel.id),
        channel: channel,
        selected: selected,
        onSelect: () => onSelect(channel.id),
        onPlay: () => onPlay(channel),
        onAction: (action) => switch (action) {
          LiveChannelAction.info => onSelect(channel.id),
          LiveChannelAction.favorite => onFavorite(channel),
          LiveChannelAction.probe => onProbe(channel),
          LiveChannelAction.epg => onEpg(channel),
          LiveChannelAction.toggle => onToggle(channel),
        },
      );

  Widget _compactPreview(BuildContext context, LiveChannel channel) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '已选 ${channel.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: channel.favorite ? '取消收藏' : '收藏',
          onPressed: () => onFavorite(channel),
          icon: Icon(channel.favorite ? Icons.star : Icons.star_outline),
        ),
        IconButton.filled(
          tooltip: channel.health.enabled ? '播放选中频道' : '重新启用',
          onPressed: !channel.health.enabled
              ? () => onToggle(channel)
              : channel.urls.isNotEmpty
              ? () => onPlay(channel)
              : null,
          icon: Icon(channel.health.enabled ? Icons.play_arrow : Icons.restore),
        ),
      ],
    ),
  );

  Widget _preview(BuildContext context, LiveChannel channel) => Card(
    margin: const EdgeInsets.fromLTRB(8, 8, 16, 16),
    child: SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.live_tv, size: 44),
          const SizedBox(height: 20),
          Text(channel.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(channel.listName, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Text(channel.health.label),
          Text(channel.health.message),
          if (channel.health.checkedAt != null)
            Text(
              '检测时间：${channel.health.checkedAt!.toLocal().toString().split('.').first}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text('${channel.urls.length} 条备用线路'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: channel.health.enabled && channel.urls.isNotEmpty
                ? () => onPlay(channel)
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放频道'),
          ),
          TextButton.icon(
            onPressed: () => onFavorite(channel),
            icon: Icon(channel.favorite ? Icons.star : Icons.star_outline),
            label: Text(channel.favorite ? '取消收藏' : '收藏频道'),
          ),
          TextButton.icon(
            onPressed: () => onEpg(channel),
            icon: const Icon(Icons.event_note),
            label: const Text('查看节目单'),
          ),
          TextButton.icon(
            onPressed: () => onProbe(channel),
            icon: const Icon(Icons.network_check),
            label: const Text('检测线路'),
          ),
          TextButton.icon(
            onPressed: () => onToggle(channel),
            icon: Icon(channel.health.enabled ? Icons.block : Icons.restore),
            label: Text(channel.health.enabled ? '停用频道' : '重新启用'),
          ),
        ],
      ),
    ),
  );
}
