import '../../supervision/presentation/sensitive_action.dart';
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
  var cancellation = CancellationToken();
  final statuses = <String, String>{};
  bool running = false;
  final unavailable = <String>{};
  final inconclusive = <String>{};
  int completed = 0, responding = 0;
  final names = <String, String>{};
  int concurrency = 8;
  late final channels = {
    for (final group in widget.channels)
      for (final entry in group.entries)
        if (!entry.health.removed) entry.id: entry,
  }.values.toList();

  Future<void> _run() async {
    cancellation = CancellationToken();
    statuses.clear();
    unavailable.clear();
    inconclusive.clear();
    completed = responding = 0;
    if (mounted) setState(() => running = true);
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

    await Future.wait(List.generate(concurrency, (_) => worker()));
    if (mounted) setState(() => running = false);
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.enableResponding ? '检测并启用停用频道' : '频道测活'),
    content: SizedBox(
      width: 600,
      height: 400,
      child: ListView.builder(
        itemCount: statuses.length + 1,
        itemBuilder: (_, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (running) const LinearProgressIndicator(),
                Text(
                  '已完成 $completed/${channels.length} · 响应 $responding · 已停用无效 ${unavailable.length} · 未确定 ${inconclusive.length}',
                ),
                DropdownButton<int>(
                  value: concurrency,
                  items: [
                    for (final count in [4, 8, 16])
                      DropdownMenuItem(value: count, child: Text('$count 路并发')),
                  ],
                  onChanged: running
                      ? null
                      : (value) => setState(() => concurrency = value!),
                ),
                const Text(
                  '同源最多 2 路连接；逐一尝试备用线路，每路最多 128 KiB / 8 秒网络时间，有媒体响应即停止。超时保留为未确定。',
                ),
                Text(
                  widget.enableResponding
                      ? '仅有媒体响应的频道自动启用；未确定保持停用，已移除频道不参与。'
                      : '内置频道仅保留有媒体响应的项；失败或未确认先停用，复检通过后恢复。手动停用项请使用“检测并启用”。',
                ),
              ],
            );
          }
          final channel = channels[index - 1];
          return ListTile(
            title: Text(names[channel.id] ?? channel.name),
            subtitle: Text(statuses[channel.id] ?? '等待检测'),
          );
        },
      ),
    ),
    actions: [
      if (!running)
        TextButton(
          onPressed: () => perform(
            context,
            () => runSensitive(
              context,
              widget.services.supervision,
              SensitiveOperation.channels,
              _run,
              needed: widget.enableResponding,
            ),
          ),
          child: Text(completed == 0 ? '开始检测' : '重新检测'),
        ),
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
