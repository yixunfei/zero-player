import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/probe_cleanup_actions.dart';
import '../application/source_probe.dart';
import '../domain/source_probe_result.dart';

final class SourceProbeDialog extends StatelessWidget {
  const SourceProbeDialog({
    super.key,
    required this.services,
    required this.probe,
  });
  final AppServices services;
  final SourceProbe probe;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: probe,
    builder: (context, _) => AlertDialog(
      title: const Text('批量探测接口'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          children: [
            if (probe.running) const LinearProgressIndicator(),
            Text(
              '完成 ${probe.results.length}/${probe.total} · '
              '可用 ${probe.results.values.where((v) => v == SourceProbeState.available).length} · '
              '明确无效 ${probe.unavailable.length}',
            ),
            const Text('API 可用不代表媒体可播放；超时和网络异常单独保留。'),
            Expanded(
              child: ListView.builder(
                itemCount: probe.statuses.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text(probe.statuses.values.elementAt(index)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!probe.running && probe.unavailable.isNotEmpty)
          ProbeCleanupActions(
            ids: probe.unavailable,
            noun: '渠道',
            onDisable: (ids) => services.sources.batch(ids, enabled: false),
            onRemove: (ids) => services.sources.batch(ids, suppressed: true),
          ),
        TextButton(
          onPressed: () {
            if (probe.running) {
              probe.cancel();
            } else {
              Navigator.pop(context);
            }
          },
          child: Text(probe.running ? '停止检测' : '关闭'),
        ),
      ],
    ),
  );
}
