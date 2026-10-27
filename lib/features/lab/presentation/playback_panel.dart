import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../application/lab_controller.dart';

final class PlaybackPanel extends StatelessWidget {
  const PlaybackPanel({super.key, required this.controller});
  final LabController controller;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Focus(
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.space) {
                controller.engine.playOrPause();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Video(controller: controller.engine.video),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: () => _seek(-10),
            icon: const Icon(Icons.replay_10),
            label: const Text('后退 10 秒'),
          ),
          StreamBuilder<bool>(
            stream: controller.engine.playing,
            initialData: false,
            builder: (context, snapshot) => FilledButton.icon(
              key: const ValueKey('play-pause'),
              onPressed: controller.engine.playOrPause,
              icon: Icon(snapshot.data! ? Icons.pause : Icons.play_arrow),
              label: Text(snapshot.data! ? '暂停' : '播放'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _seek(10),
            icon: const Icon(Icons.forward_10),
            label: const Text('前进 10 秒'),
          ),
          PopupMenuButton<double>(
            tooltip: '播放速度',
            onSelected: controller.engine.setRate,
            itemBuilder: (_) => [
              for (final rate in [0.5, 1.0, 1.5, 2.0, 3.0])
                PopupMenuItem(value: rate, child: Text('$rate 倍速')),
            ],
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('倍速'),
            ),
          ),
        ],
      ),
    ],
  );

  void _seek(int seconds) {
    final state = controller.engine.player.state;
    final target = state.position + Duration(seconds: seconds);
    controller.engine.seek(
      Duration(
        milliseconds: target.inMilliseconds.clamp(
          0,
          state.duration.inMilliseconds,
        ),
      ),
    );
  }
}
