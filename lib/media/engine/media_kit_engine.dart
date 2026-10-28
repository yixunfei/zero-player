import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../features/playback/domain/player_engine.dart';
import '../../core/network/header_policy.dart';
import '../../core/network/network_target_policy.dart';
import '../../core/platform/close_resources.dart';
import '../gateway/media_gateway.dart';

final class MediaKitEngine implements PlayerEngine {
  MediaKitEngine({
    bool videoOutput = true,
    this.gateway,
    this.isTrustedPlaylist,
  }) {
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
          _scheduleState();
        }),
      );
    }
  }
  final Player player = Player(
    configuration: const PlayerConfiguration(
      title: 'Zero Player',
      bufferSize: 8 * 1024 * 1024,
      protocolWhitelist: ['http', 'https', 'tcp', 'tls', 'crypto'],
    ),
  );
  late final VideoController video;
  final _states = StreamController<PlaybackSnapshot>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final MediaGateway? gateway;
  final bool Function(Uri)? isTrustedPlaylist;
  GatewaySession? _session;
  Future<void>? _securityReady;
  Future<void>? _disposing;
  Timer? _stateTimer;

  void _scheduleState() {
    if (_disposing != null || _states.isClosed) return;
    _stateTimer ??= Timer(const Duration(milliseconds: 50), () {
      _stateTimer = null;
      if (!_states.isClosed) _states.add(snapshot);
    });
  }

  Future<void> _configureSecurity() async {
    for (final entry in const {
      'load-scripts': 'no',
      'config': 'no',
      'load-unsafe-playlists': 'no',
      'access-references': 'no',
      'sub-auto': 'no',
      'audio-file-auto': 'no',
      'cache-on-disk': 'no',
    }.entries) {
      await _setVerified(entry.key, entry.value);
    }
  }

  Future<void> _setVerified(String key, String value) async {
    final native = player.platform as NativePlayer;
    await native.setProperty(key, value);
    if (await native.getProperty('options/$key') != value) {
      throw StateError('播放器安全选项未生效：$key');
    }
  }

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
  Future<void> open(Uri uri, {Map<String, String> headers = const {}}) async {
    NetworkTargetPolicy.validateUri(uri);
    if (_disposing != null) throw StateError('Player is closing');
    await (_securityReady ??= _configureSecurity());
    if (_disposing != null) return;
    _session?.close();
    final transport = gateway;
    if (transport != null) {
      await transport.start();
      if (_disposing != null) return;
      final session = _session = transport.createSession(
        HeaderPolicy({uri: headers}),
      )..cacheEnabled = false;
      uri = await session.openMedia(uri);
      headers = const {};
    }
    if (_disposing != null) return;
    // media_kit.open writes a temporary playlist. A single trusted media item
    // can use add/loadfile directly, keeping external playlist access disabled.
    await player.stop();
    if (_disposing != null) return;
    final trustedHls =
        gateway?.isRegisteredPlaylist(uri) == true ||
        isTrustedPlaylist?.call(uri) == true;
    // HLS needs nested reads. Only registered, rewritten manifests may use
    // them; force the HLS demuxer so a generic playlist cannot become loadfile.
    await _setVerified('access-references', trustedHls ? 'yes' : 'no');
    await _setVerified('demuxer', trustedHls ? 'lavf' : '');
    await _setVerified('demuxer-lavf-format', trustedHls ? 'hls' : '');
    if (_disposing != null) return;
    await player.add(
      Media(uri.toString(), httpHeaders: HeaderPolicy.sanitize(headers)),
    );
    if (_disposing != null) return;
    await player.jump(0);
    await player.play();
  }

  @override
  Future<void> playOrPause() => player.playOrPause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> setRate(double rate) => player.setRate(rate);
  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _stateTimer?.cancel();
    _session?.close();
    await closeResources([
      for (final subscription in _subscriptions) subscription.cancel,
      player.dispose,
      _states.close,
    ]);
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() {
    _session?.close();
    _session = null;
    return player.stop();
  }

  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);
  @override
  Future<List<int>?> screenshot() => player.screenshot();
}
