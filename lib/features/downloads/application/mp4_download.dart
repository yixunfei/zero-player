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
}) => _Mp4Transfer(
  uri,
  directory,
  http,
  policy,
  cancellation,
  maxBytes,
  reserveBytes,
  progress,
  validate,
).run();

final class _Mp4Transfer {
  _Mp4Transfer(
    this.uri,
    this.directory,
    this.http,
    this.policy,
    this.cancellation,
    this.maxBytes,
    this.reserveBytes,
    this.progress,
    this.validate,
  );
  final Uri uri;
  final Directory directory;
  final MediaHttpClient http;
  final HeaderPolicy policy;
  final CancellationToken cancellation;
  final int maxBytes;
  final void Function(int)? reserveBytes;
  final Future<void> Function(int, int, int) progress;
  final Future<void> Function(File, CancellationToken) validate;
  late final part = File(p.join(directory.path, 'video.mp4.part'));
  late final checkpoint = File(p.join(directory.path, 'mp4-state.json'));

  Future<void> run() async {
    cancellation.check();
    final state = await _readState();
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > 0 &&
        (state['uri'] != uri.toString() ||
            state['etag'] is! String ||
            (state['etag'] as String).startsWith('W/'))) {
      await part.delete();
      offset = 0;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final payload = await http.open(
        uri,
        policy: policy,
        cancellation: cancellation,
        priority: RequestPriority.background,
        range: offset > 0 ? 'bytes=$offset-' : null,
        ifRange: offset > 0 ? state['etag'] as String : null,
      );
      final response = payload.response;
      final etag = response.headers.value('etag');
      if (response.statusCode == 416) {
        await payload.body.take(0).drain<void>();
        if (_alreadyComplete(response, offset, state)) {
          _reserve(offset);
          await _finish(offset);
          return;
        }
        if (attempt == 0 && offset > 0) {
          await part.delete();
          offset = 0;
          continue;
        }
        throw const HttpException('来源拒绝下载字节范围');
      }
      var consumed = false;
      try {
        if (response.statusCode == 200) {
          // Persist the empty body before a new validator; a crash must never
          // associate the previous version's bytes with the new ETag.
          if (offset > 0) await part.writeAsBytes(const [], flush: true);
          offset = 0;
        }
        final total = _total(response, offset, state['etag']);
        if (total > maxBytes) throw const FileSystemException('下载超过容量上限');
        _reserve(offset);
        await _saveState({
          'etag': etag,
          'uri': uri.toString(),
          if (total >= 0) 'total': total,
        });
        consumed = true;
        final bytes = await _receive(payload, offset, total);
        if (total >= 0 && bytes != total) throw const HttpException('下载文件不完整');
        await _finish(bytes);
        return;
      } finally {
        if (!consumed) await payload.body.take(0).drain<void>();
      }
    }
  }

  bool _alreadyComplete(HttpClientResponse response, int offset, Map state) {
    final match = RegExp(
      r'^bytes \*/(\d+)$',
    ).firstMatch(response.headers.value('content-range') ?? '');
    final total = match == null ? null : int.tryParse(match[1]!);
    return offset > 0 &&
        total == offset &&
        response.headers.value('etag') == state['etag'] &&
        (state['total'] == null || state['total'] == total);
  }

  int _total(HttpClientResponse response, int offset, Object? oldEtag) {
    if (response.statusCode == 200) return response.contentLength;
    if (response.statusCode != 206) throw const HttpException('下载请求失败');
    final match = RegExp(
      r'^bytes (\d+)-(\d+)/(\d+)$',
    ).firstMatch(response.headers.value('content-range') ?? '');
    if (match == null) throw const FormatException('来源返回无效的下载范围');
    final start = int.parse(match[1]!);
    final end = int.parse(match[2]!);
    final total = int.parse(match[3]!);
    if (start != offset ||
        end < start ||
        end >= total ||
        (response.contentLength >= 0 &&
            response.contentLength != end - start + 1) ||
        (offset > 0 && response.headers.value('etag') != oldEtag)) {
      throw const FormatException('来源不支持安全续传或文件已变化');
    }
    return total;
  }

  Future<Map<String, dynamic>> _readState() async {
    if (!await checkpoint.exists()) return {};
    try {
      final state = jsonDecode(await checkpoint.readAsString());
      return state is Map<String, dynamic> ? state : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _saveState(Map<String, Object?> state) async {
    final temporary = File('${checkpoint.path}.part');
    await temporary.writeAsString(jsonEncode(state), flush: true);
    await temporary.rename(checkpoint.path);
  }

  void _reserve(int bytes) {
    if (bytes > maxBytes) throw const FileSystemException('下载超过容量上限');
    reserveBytes?.call(bytes);
  }

  Future<int> _receive(HttpPayload payload, int offset, int total) async {
    final sink = part.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var bytes = offset;
    var lastUpdate = DateTime.now();
    try {
      await for (final chunk in payload.body) {
        cancellation.check();
        bytes += chunk.length;
        _reserve(bytes);
        sink.add(chunk);
        if (bytes % (1024 * 1024) < chunk.length) await sink.flush();
        if (DateTime.now().difference(lastUpdate) >
            const Duration(milliseconds: 500)) {
          lastUpdate = DateTime.now();
          await progress(bytes, total < 0 ? 0 : total, bytes);
        }
      }
    } finally {
      await sink.close();
    }
    return bytes;
  }

  Future<void> _finish(int bytes) async {
    cancellation.check();
    await validate(part, cancellation);
    cancellation.check();
    final digest = '${await sha256.bind(part.openRead()).first}';
    await part.rename(p.join(directory.path, 'video.mp4'));
    await File(p.join(directory.path, 'integrity.json')).writeAsString(
      jsonEncode({'digest': digest, 'bytes': bytes}),
      flush: true,
    );
    await progress(bytes, bytes, bytes);
  }
}
