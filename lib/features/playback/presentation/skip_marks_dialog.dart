import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../application/playback_controller.dart';
import '../data/skip_repository.dart';

Future<void> showSkipMarks(
  BuildContext context,
  AppServices services,
  PlaybackController player,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        Future<void> refresh() async {
          await player.refreshSkipMarks();
          if (context.mounted) update(() {});
        }

        return AlertDialog(
          title: const Text('片段管理'),
          content: SizedBox(
            width: 620,
            height: 420,
            child: ListView(
              children: [
                SwitchListTile(
                  title: const Text('此作品启用自动跳过'),
                  value: player.workSkipEnabled,
                  onChanged: (value) => perform(context, () async {
                    await services.skips.setWorkEnabled(
                      player.seriesKey,
                      value,
                    );
                    player.workSkipEnabled = value;
                    await refresh();
                  }),
                ),
                const Text('片段绑定当前来源、线路和剧集；只在时长匹配时生效。可以编辑秒数微调，并在终点试跳暂停。'),
                for (final mark in player.marks)
                  ListTile(
                    title: Text(
                      '${mark.label} · ${clockText(mark.start)} — ${clockText(mark.end)}',
                    ),
                    leading: Checkbox(
                      value: mark.enabled,
                      onChanged: (value) => perform(context, () async {
                        await services.skips.enable(mark.id, value ?? false);
                        await refresh();
                      }),
                    ),
                    onTap: () => _edit(context, services, mark, refresh),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: '试跳到终点并暂停',
                          onPressed: () => perform(context, () async {
                            await player.engine.pause();
                            await player.seek(mark.end);
                          }),
                          icon: const Icon(Icons.skip_next),
                        ),
                        IconButton(
                          tooltip: '删除片段',
                          onPressed: () => perform(context, () async {
                            await services.skips.remove(mark.id);
                            await refresh();
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => _add(context, services, player, refresh),
                  child: const Text('按秒数添加片头 / 中段 / 片尾'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    ),
  );
}

Duration _seconds(String text) {
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value < 0) {
    throw const FormatException('请输入非负秒数');
  }
  return Duration(milliseconds: (value * 1000).round());
}

Future<void> _edit(
  BuildContext context,
  AppServices services,
  SkipMark mark,
  Future<void> Function() refresh,
) => perform(context, () async {
  final result = await inputDialog(
    context,
    '微调片段',
    ['标签', '起点（秒）', '终点（秒）'],
    initial: [
      mark.label,
      '${mark.start.inMilliseconds / 1000}',
      '${mark.end.inMilliseconds / 1000}',
    ],
  );
  if (result == null) return;
  await services.skips.edit(
    mark,
    _seconds(result[1]),
    _seconds(result[2]),
    result[0],
  );
  await refresh();
});
Future<void> _add(
  BuildContext context,
  AppServices services,
  PlaybackController player,
  Future<void> Function() refresh,
) => perform(context, () async {
  final result = await inputDialog(
    context,
    '添加片段',
    ['标签', '起点（秒）', '终点（秒）'],
    initial: ['片头', '0', '${player.originalPosition.inSeconds}'],
  );
  if (result == null) return;
  await services.skips.add(
    player.workKey,
    _seconds(result[1]),
    _seconds(result[2]),
    player.originalDuration,
    result[0],
  );
  await refresh();
});
