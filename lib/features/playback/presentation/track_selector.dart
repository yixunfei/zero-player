import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../app/widgets.dart';

Future<void> selectTracks(
  BuildContext context,
  Player player,
) => showDialog<void>(
  context: context,
  builder: (context) => StreamBuilder<Tracks>(
    stream: player.stream.tracks,
    initialData: player.state.tracks,
    builder: (context, tracks) => StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (context, current) => AlertDialog(
        title: const Text('音轨与字幕'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('音轨'),
                for (final track in tracks.data!.audio)
                  ListTile(
                    selected: current.data!.audio == track,
                    leading: Icon(
                      current.data!.audio == track
                          ? Icons.check
                          : Icons.audiotrack,
                    ),
                    title: Text(_label(track.id, track.title, track.language)),
                    onTap: () =>
                        perform(context, () => player.setAudioTrack(track)),
                  ),
                const Divider(),
                const Text('内嵌字幕'),
                for (final track in tracks.data!.subtitle)
                  ListTile(
                    selected: current.data!.subtitle == track,
                    leading: Icon(
                      current.data!.subtitle == track
                          ? Icons.check
                          : Icons.subtitles_outlined,
                    ),
                    title: Text(_label(track.id, track.title, track.language)),
                    onTap: () =>
                        perform(context, () => player.setSubtitleTrack(track)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    ),
  ),
);

String _label(String id, String? title, String? language) => switch (id) {
  'auto' => '自动选择',
  'no' => '关闭',
  _ => [
    title?.isNotEmpty == true ? title! : '轨道 $id',
    if (language?.isNotEmpty == true) language!,
  ].join(' · '),
};
