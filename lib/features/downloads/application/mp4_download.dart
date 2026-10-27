import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../core/network/media_http_client.dart';
import '../../../core/network/request_scheduler.dart';

Future<void> downloadMp4({
  required Uri uri,
  required Directory directory,
  required MediaHttpClient http,
  required HeaderPolicy policy,
  required CancellationToken cancellation,
  required int maxBytes,
  void Function(int)? reserveBytes,
  required Future<void> Function(int, int, int) progress,
  required Future<void> Function(File, CancellationToken) validate,
}) async {
  final part = File(p.join(directory.path, 'video.mp4.part'));
  final checkpoint = File(p.join(directory.path, 'mp4-state.json'));
  var offset = await part.exists() ? await part.length() : 0;
  final state = await checkpoint.exists()
      ? jsonDecode(await checkpoint.readAsString()) as Map
      : <String, Object?>{};
  if (offset > 0 && (state['etag'] == null || state['uri'] != uri.toString())) {
    await part.delete();
    offset = 0;
  }
  final response = await http.open(
    uri,
    policy: policy,
    cancellation: cancellation,
    priority: RequestPriority.background,
    range: offset > 0 ? 'bytes=$offset-' : null,
  );
  final status = response.response.statusCode;
  if (status != 200 && status != 206) {
    await response.body.take(0).drain<void>();
    throw const HttpException('下载请求失败');
  }
  final etag = response.response.headers.value('etag');
  if (offset > 0 &&
      (status != 206 ||
          etag != state['etag'] ||
          !(response.response.headers.value('content-range') ?? '').startsWith(
            'bytes $offset-',
          ))) {
    await response.body.take(0).drain<void>();
    throw const FormatException('来源不支持安全续传或文件已变化，请重新创建任务');
  }
  final expected = response.response.contentLength;
  if (expected >= 0 && offset + expected > maxBytes) {
    await response.body.take(0).drain<void>();
    throw const FileSystemException('下载超过容量上限');
  }
  await checkpoint.writeAsString(
    jsonEncode({'etag': etag, 'uri': uri.toString()}),
    flush: true,
  );
  final sink = part.openWrite(
    mode: offset > 0 ? FileMode.append : FileMode.write,
  );
  var bytes = offset;
  var lastUpdate = DateTime.now();
  try {
    await for (final chunk in response.body) {
      cancellation.check();
      bytes += chunk.length;
      if (bytes > maxBytes) throw const FileSystemException('下载超过容量上限');
      reserveBytes?.call(bytes);
      sink.add(chunk);
      // Flush in batches, keeping memory bounded without a disk flush per packet.
      if (bytes % (1024 * 1024) < chunk.length) await sink.flush();
      if (DateTime.now().difference(lastUpdate) >
          const Duration(milliseconds: 500)) {
        lastUpdate = DateTime.now();
        await progress(bytes, expected < 0 ? 0 : offset + expected, bytes);
      }
    }
  } finally {
    await sink.close();
  }
  if (expected >= 0 && bytes - offset != expected) {
    throw const HttpException('下载文件不完整');
  }
  cancellation.check();
  await validate(part, cancellation);
  cancellation.check();
  final digest = '${await sha256.bind(part.openRead()).first}';
  await part.rename(p.join(directory.path, 'video.mp4'));
  await File(
    p.join(directory.path, 'integrity.json'),
  ).writeAsString(jsonEncode({'digest': digest, 'bytes': bytes}), flush: true);
  await progress(bytes, bytes, bytes);
}
