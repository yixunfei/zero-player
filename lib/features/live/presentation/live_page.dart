import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/platform/file_transfer.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../playback/application/playback_controller.dart';
import '../data/m3u_parser.dart';
import '../domain/live_channel.dart';
import 'live_probe_dialog.dart';
import 'tonkiang_dialog.dart';
import 'live_browser.dart';
import 'live_subscriptions_dialog.dart';
import '../domain/channel_order.dart';

final class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.services});
  final AppServices services;
  @override
  State<LivePage> createState() => _LivePageState();
}

final class _LivePageState extends State<LivePage> {
  late Future<List<LiveChannel>> future;
  late final StreamSubscription<void> changes;
  String query = '';
  String group = '央视';
  String? _selectedId;
  final _scroll = ScrollController();
  final _searchText = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
    unawaited(widget.services.builtinLive.refresh(onlyMissing: true));
    changes = widget.services.db.changes.listen((_) {
      if (mounted) setState(_load);
    });
  }

  void _load() {
    future = widget.services.live.channels();
  }

  @override
  void dispose() {
    changes.cancel();
    _scroll.dispose();
    _searchText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchText,
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  labelText: '查找电视频道',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: '清空频道搜索',
                    onPressed: () {
                      _searchText.clear();
                      setState(() => query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              tooltip: '检测当前分组',
              onPressed: _probe,
              icon: const Icon(Icons.network_check),
            ),
            PopupMenuButton<String>(
              tooltip: '直播管理',
              onSelected: _manage,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('添加 M3U / TXT')),
                PopupMenuItem(value: 'lists', child: Text('管理订阅 / EPG')),
                PopupMenuItem(value: 'probeAll', child: Text('检测所有频道')),
                PopupMenuItem(value: 'restore', child: Text('恢复 / 刷新内置直播')),
                PopupMenuItem(value: 'search', child: Text('在线电视 IPTV 搜索')),
                PopupMenuItem(value: 'export', child: Text('导出频道')),
              ],
            ),
          ],
        ),
      ),
      Expanded(
        child: LoadView(
          future: future,
          retry: () => setState(_load),
          builder: (channels) => channels.isEmpty
              ? EmptyState(
                  '还没有可浏览的频道',
                  '请在订阅管理中启用或刷新列表，也可添加 M3U / TXT；首次下载会自动显示频道。',
                  action: FilledButton(
                    onPressed: () => _manage('lists'),
                    child: const Text('管理直播订阅'),
                  ),
                )
              : LiveBrowser(
                  channels: channels,
                  group: group,
                  query: query,
                  controller: _scroll,
                  selectedId: _selectedId,
                  onSelect: (id) => setState(() => _selectedId = id),
                  onGroup: (value) {
                    setState(() {
                      group = value;
                      _selectedId = null;
                    });
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  },
                  onPlay: _play,
                  onFavorite: (c) => perform(
                    context,
                    () => widget.services.live.favorite(c, !c.favorite),
                  ),
                  onToggle: _toggle,
                  onEpg: _epg,
                  onProbe: (c) => _showProbe([c]),
                ),
        ),
      ),
    ],
  );

  void _manage(String action) {
    switch (action) {
      case 'add':
        _add();
      case 'lists':
        _lists();
      case 'probeAll':
        _probe(all: true);
      case 'search':
        showTonkiang(context, widget.services);
      case 'restore':
        perform(context, () async {
          await widget.services.builtinLive.initialize(restore: true);
          await widget.services.builtinLive.refresh();
        }, success: '刷新完成，失败详情见订阅管理');
      case 'export':
        perform(context, () async {
          final channels = await widget.services.live.channels();
          await FileTransfer.saveText(
            'zero-player-live.m3u',
            exportM3u(
              channels
                  .where((c) => c.health.enabled && !c.health.removed)
                  .toList(),
            ),
          );
        });
    }
  }

  Future<void> _toggle(LiveChannel channel) => perform(context, () async {
    if (channel.health.enabled &&
        !await confirm(context, '停用频道', '停用后从正常浏览和换台列表隐藏，收藏保留；可在已停用分组恢复。')) {
      return;
    }
    await widget.services.liveHealth.setEnabled(
      channel.preferenceIds,
      !channel.health.enabled || channel.health.removed,
    );
  });

  Future<void> _play(LiveChannel channel) => perform(context, () async {
    if (!channel.health.enabled ||
        channel.health.removed ||
        channel.urls.isEmpty) {
      return;
    }
    await widget.services.live.watched(channel);
    final channels = (await widget.services.live.channels())
        .where(
          (c) => c.urls.isNotEmpty && c.health.enabled && !c.health.removed,
        )
        .toList();
    if (!mounted) return;
    final item = CatalogItem(
      sourceId: 'live',
      id: channel.id,
      title: '直播',
      lines: [
        for (final current in channels)
          PlayLine(current.name, [
            for (final (i, url) in current.playbackUrls.indexed)
              Episode('线路 ${i + 1}', url),
          ]),
      ],
    );
    context.push(
      '/player',
      extra: PlaybackRequest(
        item,
        live: true,
        line: channels.indexWhere((c) => c.id == channel.id),
        headersByUri: {
          for (final c in channels)
            for (final uri in c.urls) uri: c.headersFor(uri),
        },
      ),
    );
  });
  Future<void> _probe({bool all = false}) => perform(context, () async {
    final channels = (await widget.services.live.channels())
        .where(
          (c) =>
              c.urls.isNotEmpty &&
              matchesChannel(c, all ? '全部' : group, all ? '' : query),
        )
        .expand((c) => c.entries)
        .where((c) => c.urls.isNotEmpty)
        .toList();
    if (!mounted) return;
    if (channels.isEmpty) {
      message(context, '当前分组没有可检测频道');
      return;
    }
    if (!await confirm(
      context,
      '探测当前分组',
      '将探测 ${channels.length} 个频道来源，每来源最多检查 3 条线路，上限约 ${(channels.length * .75).ceil()} MiB，可随时停止；未测完的备用线路不会判为无效。',
    )) {
      return;
    }
    if (mounted) await _showProbe(channels);
  });
  Future<void> _showProbe(List<LiveChannel> channels) => showDialog<void>(
    context: context,
    builder: (_) =>
        LiveProbeDialog(services: widget.services, channels: channels),
  );
  Future<void> _add() => perform(context, () async {
    final values = await inputDialog(context, '添加直播订阅', [
      '名称',
      'M3U / TXT URL',
      'XMLTV / XMLTV.GZ URL（可留空）',
    ]);
    if (values == null) return;
    await widget.services.live.import(
      values[0],
      Uri.parse(values[1]),
      epg: values[2].isEmpty ? null : Uri.parse(values[2]),
    );
  }, success: '直播列表已保存');
  Future<void> _epg(LiveChannel channel) => perform(context, () async {
    final items = await widget.services.live.schedule(channel);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${channel.name} · 节目单'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (items.isEmpty)
                  const Text('当前没有节目单，请检查 XMLTV 地址与 tvg-id 匹配'),
                for (final item in items)
                  ListTile(
                    title: Text(item.title),
                    subtitle: Text(
                      '${item.start.toLocal()} — ${item.end.toLocal()}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  });
  Future<void> _lists() => showDialog<void>(
    context: context,
    builder: (_) => LiveSubscriptionsDialog(services: widget.services),
  );
}
