import 'dart:async';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../core/network/media_http_client.dart';
import '../../../media/network/media_probe.dart';
import '../data/live_health_repository.dart';
import '../domain/live_channel.dart';
import '../domain/live_health.dart';

final class LiveProbe {
  LiveProbe(
    this.http,
    this.repository, {
    this.networkTimeout = const Duration(seconds: 20),
  });
  final MediaHttpClient http;
  final LiveHealthRepository repository;
  final Duration networkTimeout;
  final _active = <Future<LiveHealth>>{};
  final _tokens = <CancellationToken>{};
  bool _closed = false;

  Future<LiveHealth> check(LiveChannel channel, CancellationToken token) {
    if (_closed) throw StateError('直播检测已关闭');
    final local = CancellationToken();
    final unlink = token.listen(local.cancel);
    _tokens.add(local);
    late final Future<LiveHealth> work;
    work = _check(channel, local).whenComplete(() {
      unlink();
      _tokens.remove(local);
      _active.remove(work);
    });
    _active.add(work);
    return work;
  }

  Future<void> close() async {
    _closed = true;
    for (final token in _tokens.toList()) {
      token.cancel();
    }
    await Future.wait(
      _active.toList().map((work) async {
        try {
          await work;
        } catch (_) {
          /* Cancellation is expected on shutdown. */
        }
      }),
    );
  }

  Future<LiveHealth> _check(
    LiveChannel channel,
    CancellationToken token,
  ) async {
    var uncertain = channel.urls.length > 3;
    var message = '频道没有可播放线路';
    for (final uri in channel.urls.take(3)) {
      token.check();
      try {
        final result = await probeMedia(
          http,
          uri,
          HeaderPolicy({uri: channel.headersFor(uri)}),
          token,
          availabilityOnly: true,
          maxBytes: 256 * 1024,
          networkTimeout: networkTimeout,
        );
        token.check();
        final health = LiveHealth(
          availability: LiveAvailability.responding,
          latencyMs: result.firstByte.inMilliseconds,
          preferredUrl: uri.toString(),
          message: '已收到媒体数据，未验证完整解码',
        );
        await repository.record(channel, health);
        return health;
      } catch (error) {
        token.check();
        uncertain |= error is! FormatException;
        message = error is FormatException
            ? error.message
            : error is ProbeInconclusive
            ? error.message
            : '连接或检测超时，仍可尝试播放';
      }
    }
    token.check();
    final result = LiveHealth(
      availability: uncertain
          ? LiveAvailability.inconclusive
          : LiveAvailability.unavailable,
      message: message,
    );
    await repository.record(channel, result);
    return result;
  }
}
