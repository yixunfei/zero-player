import 'package:flutter/material.dart';

const playerOrientationLabels = {
  'system': '跟随系统',
  'landscape': '横屏播放',
  'auto': '自动旋转',
};

final class PlayerOrientationMenu extends StatelessWidget {
  const PlayerOrientationMenu({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '屏幕方向：${playerOrientationLabels[value]}',
    initialValue: value,
    onSelected: onChanged,
    icon: Icon(
      value == 'landscape'
          ? Icons.screen_lock_landscape
          : Icons.screen_rotation,
    ),
    itemBuilder: (_) => [
      for (final entry in playerOrientationLabels.entries)
        CheckedPopupMenuItem(
          value: entry.key,
          checked: value == entry.key,
          child: Text(entry.value),
        ),
    ],
  );
}
