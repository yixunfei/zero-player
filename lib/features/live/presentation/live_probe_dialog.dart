import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../app/widgets.dart';
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
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    var index = 0;
    Future<void> worker() async {
      while (index < widget.channels.length && !cancellation.isCancelled) {
        final channel = widget.channels[index++];
        names[channel.id] = channel.name;
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
          if (!cancellation.isCancelled) statuses[channel.id] = '检测未完成';
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
        TextButton(
          onPressed: () => perform(context, () async {
            if (!await confirm(
              context,
              '停用检测不可用频道',
              '将停用 ${unavailable.length} 个明确不可用频道，收藏保留，可在已停用分组恢复。',
            )) {
              return;
            }
            await widget.services.liveHealth.setEnabled(unavailable, false);
            if (mounted) {
              setState(() => unavailable.clear());
            }
          }),
          child: const Text('停用不可用频道'),
        ),
      TextButton(
        onPressed: () {
          cancellation.cancel();
          Navigator.pop(context);
        },
        child: const Text('停止 / 关闭'),
      ),
    ],
  );
}
