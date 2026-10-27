import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../features/playback/domain/player_engine.dart';

final class MediaKitEngine implements PlayerEngine {
  MediaKitEngine({bool videoOutput = true}) {
    if (videoOutput) video = VideoController(player);
    for (final stream in <Stream<dynamic>>[
      player.stream.position,
      player.stream.duration,
      player.stream.playing,
      player.stream.buffering,
      player.stream.completed,
      player.stream.rate,
      player.stream.volume,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          if (!_states.isClosed) _states.add(snapshot);
        }),
      );
    }
  }
  final Player player = Player(
    configuration: const PlayerConfiguration(
      title: 'Zero Player',
      bufferSize: 8 * 1024 * 1024,
    ),
  );
  late final VideoController video;
  final _states = StreamController<PlaybackSnapshot>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  @override
  Stream<PlaybackSnapshot> get states => _states.stream;
  @override
  PlaybackSnapshot get snapshot => PlaybackSnapshot(
    position: player.state.position,
    duration: player.state.duration,
    playing: player.state.playing,
    buffering: player.state.buffering,
    completed: player.state.completed,
    rate: player.state.rate,
    volume: player.state.volume,
  );

  @override
  Stream<Duration> get position => player.stream.position;
  @override
  Stream<Duration> get duration => player.stream.duration;
  @override
  Stream<bool> get playing => player.stream.playing;
  @override
  Stream<String> get errors => player.stream.error;
  @override
  Future<void> open(Uri uri, {Map<String, String> headers = const {}}) =>
      player.open(Media(uri.toString(), httpHeaders: headers));
  @override
  Future<void> playOrPause() => player.playOrPause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> setRate(double rate) => player.setRate(rate);
  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _states.close();
    await player.dispose();
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);
  @override
  Future<List<int>?> screenshot() => player.screenshot();
}
