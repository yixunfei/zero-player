import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../application/playback_controller.dart';

Future<void> selectQuality(
  BuildContext context,
  PlaybackController player,
) async {
  final choices = player.qualities;
  if (choices.isEmpty) {
    message(context, '当前来源提供单一画质；可在播放设置中切换线路或来源');
    return;
  }
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('选择画质'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, ''),
          child: Text('自动${player.request?.quality == null ? ' · 当前' : ''}'),
        ),
        for (final quality in choices)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, quality.uri.toString()),
            child: Text(
              '${quality.label}${player.request?.quality == quality.uri ? ' · 当前' : ''}',
            ),
          ),
      ],
    ),
  );
  if (choice != null && context.mounted) {
    await perform(
      context,
      () => player.changeQuality(choice.isEmpty ? null : Uri.parse(choice)),
    );
  }
}
