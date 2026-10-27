import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/network/cancellation_token.dart';
import '../data/tonkiang_service.dart';
import 'tonkiang_dialog.dart';

final class LiveSubscriptionsDialog extends StatefulWidget {
  const LiveSubscriptionsDialog({super.key, required this.services});
  final AppServices services;
  @override
  State<LiveSubscriptionsDialog> createState() =>
      _LiveSubscriptionsDialogState();
}

final class _LiveSubscriptionsDialogState
    extends State<LiveSubscriptionsDialog> {
  late Future<List<Map<String, Object?>>> _lists;
  late final StreamSubscription<void> _changes;
  final _refreshing = <String>{};
  final _token = CancellationToken();
  @override
  void initState() {
    super.initState();
    _lists = widget.services.live.lists();
    _changes = widget.services.db.changes.listen((_) {
      if (mounted) {
        setState(() {
          _lists = widget.services.live.lists();
        });
      }
    });
  }

  @override
  void dispose() {
    _token.cancel();
    _changes.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('直播订阅'),
    content: SizedBox(
      width: 600,
      height: 480,
      child: LoadView(
        future: _lists,
        builder: (lists) => ListView(
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('停用订阅会隐藏其频道并暂停自动刷新，收藏和检测记录保留。列表可下载不等于每个频道可播放。'),
            ),
            if (lists.isEmpty) const Text('还没有直播订阅'),
            for (final row in lists) _subscription(row),
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
  );

  Widget _subscription(Map<String, Object?> row) {
    final id = row['id'] as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: Text(row['name'] as String),
              value: row['enabled'] == 1,
              subtitle: Text(row['enabled'] == 1 ? '已启用' : '已停用'),
              onChanged: (enabled) => perform(context, () async {
                await widget.services.live.setListEnabled(id, enabled);
                if (enabled && row['snapshot'] == null && mounted) {
                  await _refresh(row);
                }
              }),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                row['error'] as String? ?? '已保存频道列表',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _refreshing.contains(id)
                      ? null
                      : () => _refresh(row),
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    _refreshing.contains(id) ? '检测 / 刷新中…' : '检测 / 刷新列表与 EPG',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _remove(id),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('移除订阅'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh(Map<String, Object?> row) => perform(context, () async {
    final id = row['id'] as String;
    if (!_refreshing.add(id)) return;
    setState(() {});
    try {
      final uri = Uri.parse(row['url'] as String);
      if (uri.host == TonkiangService.origin.host) {
        await showTonkiang(
          context,
          widget.services,
          keyword: uri.queryParameters['keyword'] ?? '',
        );
      } else {
        await widget.services.live.import(
          row['name'] as String,
          uri,
          cancellation: _token,
          existingOnly: true,
          headers: await widget.services.builtinLive.headersFor(uri),
          epg: row['epg_url'] == null
              ? null
              : Uri.parse(row['epg_url'] as String),
        );
      }
    } finally {
      _refreshing.remove(id);
      if (mounted) setState(() {});
    }
  });

  Future<void> _remove(String id) => perform(context, () async {
    if (await confirm(context, '移除直播订阅', '移除此列表及频道，收藏标记会保留供以后恢复。')) {
      await widget.services.live.removeList(id);
    }
  });
}
