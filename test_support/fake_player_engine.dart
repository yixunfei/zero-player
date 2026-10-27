import 'dart:async';
import 'package:zero_player/features/playback/domain/player_engine.dart';

final class FakePlayerEngine implements PlayerEngine {
  FakePlayerEngine({this.onVolume});
  final Future<void> Function(double)? onVolume;
  final changes = StreamController<PlaybackSnapshot>.broadcast();
  final failures = StreamController<String>.broadcast();
  int opens = 0;
  final seeks = <Duration>[];
  @override
  PlaybackSnapshot snapshot = const PlaybackSnapshot();
  void emit(PlaybackSnapshot state) {
    snapshot = state;
    changes.add(state);
  }

  void change({Duration? position, bool? playing, double? rate}) => emit(
    PlaybackSnapshot(
      position: position ?? snapshot.position,
      duration: snapshot.duration,
      playing: playing ?? snapshot.playing,
      rate: rate ?? snapshot.rate,
    ),
  );
  @override
  Stream<PlaybackSnapshot> get states => changes.stream;
  @override
  Stream<Duration> get position => states.map((s) => s.position);
  @override
  Stream<Duration> get duration => states.map((s) => s.duration);
  @override
  Stream<bool> get playing => states.map((s) => s.playing);
  @override
  Stream<String> get errors => failures.stream;
  @override
  Future<void> open(Uri uri, {Map<String, String> headers = const {}}) async {
    opens++;
    emit(
      const PlaybackSnapshot(duration: Duration(seconds: 30), playing: true),
    );
  }

  @override
  Future<void> playOrPause() async => change(playing: !snapshot.playing);
  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    change(position: value);
  }

  @override
  Future<void> setRate(double value) async => change(rate: value);
  @override
  Future<void> dispose() async {
    await changes.close();
    await failures.close();
  }

  @override
  Future<void> play() async => change(playing: true);
  @override
  Future<void> pause() async => change(playing: false);
  @override
  Future<void> stop() async => emit(const PlaybackSnapshot());
  @override
  Future<void> setVolume(double value) async => onVolume?.call(value);
  @override
  Future<List<int>?> screenshot() async => null;
}
