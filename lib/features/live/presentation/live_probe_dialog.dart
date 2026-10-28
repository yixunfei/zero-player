import '../../supervision/presentation/sensitive_action.dart';
import 'dart:async';
import '../../../app/widgets.dart';
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
    this.enableResponding = false,
  });
  final AppServices services;
  final List<LiveChannel> channels;
  final bool enableResponding;
  @override
  State<LiveProbeDialog> createState() => _LiveProbeDialogState();
}

final class _LiveProbeDialogState extends State<LiveProbeDialog> {
  final cancellation = CancellationToken();
  final statuses = <String, String>{};
  bool running = true;
  final unavailable = <String>{};
  final inconclusive = <String>{};
  int completed = 0, responding = 0;
  final names = <String, String>{};
  late final channels = {
    for (final group in widget.channels)
      for (final entry in group.entries)
        if (!entry.health.removed) entry.id: entry,
  }.values.toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        perform(
          context,
          () => runSensitive(
            context,
            widget.services.supervision,
            SensitiveOperation.channels,
            _run,
            needed: widget.enableResponding,
          ),
        ).whenComplete(() {
          if (mounted) setState(() => running = false);
        }),
      );
    });
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
            enableResponding: widget.enableResponding,
          );
          if (result.availability == LiveAvailability.unavailable) {
            unavailable.add(channel.id);
          }
          if (result.availability == LiveAvailability.inconclusive) {
            inconclusive.add(channel.id);
          }
          if (result.availability == LiveAvailability.responding) responding++;
          completed++;
          statuses[channel.id] = result.availabilityLabel;
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
    title: Text(widget.enableResponding ? '检测并启用停用频道' : '直播测活'),
    content: SizedBox(
      width: 600,
      height: 400,
      child: ListView(
        children: [
          if (running) const LinearProgressIndicator(),
          Text(
            '已完成 $completed/${channels.length} · 响应 $responding · 已停用无效 ${unavailable.length} · 未确定 ${inconclusive.length}',
          ),
          const Text(
            '并发 2；每频道最多尝试 3 条线路，每路 256 KiB / 20 秒网络时间。只要一条响应即通过；超时及未测完为未确定。',
          ),
          Text(
            widget.enableResponding
                ? '仅有媒体响应的频道自动启用；未确定保持停用，已移除频道不参与。'
                : '明确不可用的频道自动停用；未确定保持原状态，可在检测结束后一键停用。',
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
      if (!running && inconclusive.isNotEmpty)
        TextButton(
          onPressed: () async {
            await widget.services.liveHealth.setEnabled(inconclusive, false);
            if (mounted) setState(inconclusive.clear);
          },
          child: Text('一键停用未确定 (${inconclusive.length})'),
        ),
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
