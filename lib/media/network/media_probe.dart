import 'dart:convert';
import 'dart:async';
import '../../core/network/network_budget.dart';
import '../../core/network/cancellation_token.dart';
import '../../core/network/header_policy.dart';
import '../../core/network/media_http_client.dart';
import '../../core/network/request_scheduler.dart';
import '../hls/hls_manifest.dart';

final class ProbeResult {
  const ProbeResult(this.firstByte, this.bytes, this.elapsed, this.resolution);
  final Duration firstByte;
  final int bytes;
  final Duration elapsed;
  final String? resolution;
  double get kibPerSecond => elapsed.inMicroseconds <= 0
      ? 0
      : bytes / 1024 / (elapsed.inMicroseconds / 1000000);
}

/// Limits and temporary server failures do not prove media is unavailable.
final class ProbeInconclusive implements Exception {
  const ProbeInconclusive(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Availability stops at the first media payload; throughput sampling is separate.
Future<ProbeResult> probeMedia(
  MediaHttpClient http,
  Uri uri,
  HeaderPolicy policy,
  CancellationToken token, {
  int maxBytes = 2 * 1024 * 1024,
  bool availabilityOnly = false,
  Duration networkTimeout = const Duration(seconds: 20),
}) async {
  final local = CancellationToken();
  final unlink = token.listen(local.cancel);
  final budget = NetworkBudget(networkTimeout, local);
  try {
    return await _probe(
      http,
      uri,
      policy,
      local,
      budget,
      maxBytes: maxBytes,
      availabilityOnly: availabilityOnly,
    );
  } on Object {
    if (local.isCancelled && !token.isCancelled) {
      throw TimeoutException('检测超时，仍可尝试播放');
    }
    rethrow;
  } finally {
    budget.dispose();
    unlink();
  }
}

Future<ProbeResult> _probe(
  MediaHttpClient http,
  Uri uri,
  HeaderPolicy policy,
  CancellationToken token,
  NetworkBudget budget, {
  required int maxBytes,
  required bool availabilityOnly,
}) async {
  var bytes = 0;
  String? resolution;
  for (var depth = 0; depth < 4; depth++) {
    token.check();
    final response = await http.open(
      uri,
      policy: policy,
      cancellation: token,
      priority: RequestPriority.interactive,
      onActivity: budget.activity,
    );
    final status = response.response.statusCode;
    if (status != 200 && status != 206) {
      await response.body.take(0).drain<void>();
      if (status >= 500 || {408, 425, 429}.contains(status)) {
        throw ProbeInconclusive('媒体服务器暂忙 HTTP $status，仍可尝试播放');
      }
      throw FormatException('媒体请求失败 HTTP $status');
    }
    final type = response.response.headers.contentType?.mimeType;
    if (type == 'text/html' || type == 'application/json') {
      await response.body.take(0).drain<void>();
      throw const FormatException('地址返回了网页或错误信息');
    }
    final sample = await _readSample(
      response,
      maxBytes - bytes,
      budget.clock,
      availabilityOnly,
      type,
    );
    budget.activity(false);
    bytes += sample.content.length;
    if (!sample.manifest) {
      if (sample.content.isEmpty) throw const FormatException('媒体响应为空');
      return ProbeResult(
        sample.firstByte,
        bytes,
        budget.clock.elapsed,
        resolution,
      );
    }
    final text = utf8.decode(sample.content);
    final parsed = HlsManifest.parse(text, response.uri);
    resolution ??= RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(text)?[1];
    if (bytes >= maxBytes) throw const ProbeInconclusive('清单超过探测流量上限');
    if (parsed.isMaster) {
      if (parsed.playlistUris.isEmpty) throw const FormatException('没有播放变体');
      uri = parsed.playlistUris.first;
    } else {
      final media = parsed.lines.firstWhere(
        (l) => l.isNotEmpty && !l.startsWith('#'),
        orElse: () => '',
      );
      if (media.isEmpty) throw const FormatException('没有媒体分片');
      uri = parsed.baseUri.resolve(media);
    }
  }
  throw const ProbeInconclusive('清单层级超过探测限制');
}

Future<({List<int> content, bool manifest, Duration firstByte})> _readSample(
  HttpPayload response,
  int remaining,
  Stopwatch clock,
  bool quick,
  String? type,
) async {
  final content = <int>[];
  Duration? firstByte;
  bool? manifest =
      response.uri.path.toLowerCase().endsWith('.m3u8') ||
          (type?.contains('mpegurl') ?? false)
      ? true
      : null;
  await for (final chunk in response.body) {
    if (chunk.isEmpty) continue;
    firstByte ??= clock.elapsed;
    content.addAll(chunk.take(remaining - content.length));
    if (manifest == null && content.length >= 16) {
      final prefix = utf8
          .decode(content.take(64).toList(), allowMalformed: true)
          .trimLeft();
      manifest = prefix.startsWith('#EXTM3U');
      if (prefix.startsWith('<') || prefix.startsWith('{')) {
        throw const FormatException('地址返回了网页或错误信息');
      }
    }
    if (content.length >= remaining || (quick && manifest == false)) break;
  }
  manifest ??= utf8
      .decode(content, allowMalformed: true)
      .trimLeft()
      .startsWith('#EXTM3U');
  return (
    content: content,
    manifest: manifest,
    firstByte: firstByte ?? clock.elapsed,
  );
}
