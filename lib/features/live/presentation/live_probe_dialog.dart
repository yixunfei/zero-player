import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../app/probe_cleanup_actions.dart';
import '../domain/live_health.dart';

import '../domain/live_channel.dart';

final class LiveProbeDialog extends StatefulWidget {
  const LiveProbeDialog({
    super.key,
    required this.services,
    required this.channels,
  });
  final AppServices services;
  final List<LiveChannel> channels;
  @override
  State<LiveProbeDialog> createState() => _LiveProbeDialogState();
}

final class _LiveProbeDialogState extends State<LiveProbeDialog> {
  final cancellation = CancellationToken();
  final statuses = <String, String>{};
  bool running = true;
  final unavailable = <String>{};
  final names = <String, String>{};
  late final channels = {
    for (final group in widget.channels)
      for (final entry in group.entries)
        if (entry.urls.isNotEmpty) entry.id: entry,
  }.values.toList();
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    var index = 0;
    Future<void> worker() async {
      while (index < channels.length && !cancellation.isCancelled) {
        final channel = channels[index++];
        names[channel.id] = '${channel.name} · ${channel.listName}';
        if (mounted) setState(() => statuses[channel.id] = '检测中');
        try {
          final result = await widget.services.liveProbe.check(
            channel,
            cancellation,
          );
          if (result.availability == LiveAvailability.unavailable) {
            unavailable.add(channel.id);
          }
          statuses[channel.id] = result.label;
        } catch (_) {
          statuses[channel.id] = cancellation.isCancelled ? '已取消' : '检测未完成';
        }
        if (mounted) setState(() {});
      }
    }

    await Future.wait([worker(), worker()]);
    if (mounted) setState(() => running = false);
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('直播测活'),
    content: SizedBox(
      width: 600,
      height: 400,
      child: ListView(
        children: [
          if (running) const LinearProgressIndicator(),
          Text(
            '已开始 ${statuses.length}/${channels.length} 个频道来源 · 明确无效 ${unavailable.length}',
          ),
          const Text(
            '并发 2；每频道最多尝试 3 条线路，每路 256 KiB / 20 秒网络时间。只要一条响应即通过；超时及未测完为未确定。',
          ),
          for (final entry in statuses.entries)
            ListTile(
              title: Text(names[entry.key] ?? entry.key),
              subtitle: Text(entry.value),
            ),
        ],
      ),
    ),
    actions: [
      if (!running && unavailable.isNotEmpty)
        ProbeCleanupActions(
          ids: unavailable,
          noun: '频道来源',
          onDisable: (ids) => widget.services.liveHealth.setEnabled(ids, false),
          onRemove: (ids) => widget.services.liveHealth.setRemoved(ids, true),
        ),
      TextButton(
        onPressed: () {
          if (running) {
            cancellation.cancel();
          } else {
            Navigator.pop(context);
          }
        },
        child: Text(running ? '停止检测' : '关闭'),
      ),
    ],
  );
}
