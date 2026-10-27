import 'dart:convert';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../core/network/media_http_client.dart';
import '../../../core/network/request_scheduler.dart';

/// Only inspect a bounded prefix; CDN endpoints need not have file extensions.
Future<bool> isMp4Download(
  Uri uri,
  MediaHttpClient http,
  HeaderPolicy policy,
  CancellationToken cancellation,
) async {
  if (uri.path.toLowerCase().endsWith('.mp4')) return true;
  if (uri.path.toLowerCase().endsWith('.m3u8')) return false;
  final payload = await http.open(
    uri,
    policy: policy,
    range: 'bytes=0-511',
    cancellation: cancellation,
    priority: RequestPriority.background,
  );
  final bytes = <int>[];
  await for (final chunk in payload.body) {
    bytes.addAll(chunk.take(512 - bytes.length));
    if (bytes.length >= 512) break;
  }
  if (payload.response.statusCode != 200 &&
      payload.response.statusCode != 206) {
    throw const FormatException('下载地址暂不可用');
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
    return true;
  }
  if (utf8
      .decode(bytes, allowMalformed: true)
      .trimLeft()
      .startsWith('#EXTM3U')) {
    return false;
  }
  throw const FormatException('离线下载仅支持 HLS 点播或 MP4 媒体');
}
