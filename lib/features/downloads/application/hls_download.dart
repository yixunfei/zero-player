import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../core/network/media_http_client.dart';
import '../../../core/network/request_scheduler.dart';
import '../../../media/cache/resource_identity.dart';
import '../../../media/cache/segment_fetcher.dart';
import '../../../media/hls/hls_manifest.dart';
import '../../../media/hls/offline_rewriter.dart';
import '../../sources/domain/video_source.dart';

final class HlsDownload {
  HlsDownload({
    required this.id,
    required this.directory,
    required this.fetcher,
    required this.http,
    required this.policy,
    required this.cancellation,
    required this.onProgress,
    required this.maxBytes,
    this.reserveBytes,
  });
  final String id;
  final Directory directory;
  final SegmentFetcher fetcher;
  final MediaHttpClient http;
  final HeaderPolicy policy;
  final CancellationToken cancellation;
  final Future<void> Function(int, int, int) onProgress;
  final int maxBytes;
  final void Function(int)? reserveBytes;
  final resources = <String, Map<String, String>>{};
  final _visited = <Uri, String>{};
  final _active = <Uri>{};
  final _fingerprints = <String, String>{};
  int bytes = 0;
  int completed = 0;

  Future<String> run(Uri uri) async {
    final checkpoint = File(p.join(directory.path, 'checkpoints.json'));
    if (await checkpoint.exists()) {
      _fingerprints.addAll(
        Map<String, String>.from(jsonDecode(await checkpoint.readAsString())),
      );
    }
    final root = await _manifest(uri, 0);
    cancellation.check();
    for (final value in resources.values) {
      if (value['key'] != null) await fetcher.store.verify(value['key']!);
    }
    await _save('resources.json', jsonEncode(resources));
    await fetcher.store.retainPins(
      id,
      resources.values.map((v) => v['key']).whereType<String>().toSet(),
    );
    return root;
  }

  Future<String> _manifest(Uri uri, int depth) async {
    cancellation.check();
    if (_active.contains(uri)) throw const FormatException('媒体清单包含循环引用');
    if (depth > 5 || _visited.length >= 100) {
      throw const FormatException('媒体清单递归超过限制');
    }
    if (_visited.containsKey(uri)) return _visited[uri]!;
    final payload = await http.open(
      uri,
      policy: policy,
      cancellation: cancellation,
      priority: RequestPriority.background,
    );
    if (payload.response.statusCode != 200) {
      await payload.body.take(0).drain<void>();
      throw const HttpException('无法获取下载清单');
    }
    final body = <int>[];
    await for (final chunk in payload.body) {
      if (body.length + chunk.length > 2 * 1024 * 1024) {
        throw const FormatException('清单过大');
      }
      body.addAll(chunk);
    }
    final text = utf8.decode(body);
    final fingerprint = stableId(text);
    final old = _fingerprints[uri.toString()];
    if (old != null && old != fingerprint) {
      throw const FormatException('媒体清单已变化，请重新创建下载以避免混合版本');
    }
    _fingerprints[uri.toString()] = fingerprint;
    await _save('checkpoints.json', jsonEncode(_fingerprints));
    var manifest = HlsManifest.parse(text, payload.uri);
    if (!manifest.isMaster && !manifest.isComplete) {
      throw const FormatException('动态直播清单不支持整集离线下载');
    }
    manifest = selectOfflineVariant(manifest);
    final name = '${stableId(uri.toString())}.m3u8';
    _visited[uri] = name;
    _active.add(uri);
    final output = await rewriteOffline(manifest, (
      resource, {
      range,
      playlist = false,
    }) async {
      cancellation.check();
      if (playlist) return Uri(path: await _manifest(resource, depth + 1));
      return Uri(path: await _segment(resource, range));
    });
    await _save(name, output);
    resources[name] = {'local': name, 'digest': stableId(output)};
    _active.remove(uri);
    return name;
  }

  Future<String> _segment(Uri uri, String? range) async {
    final key = resourceIdentity(uri, policy.identityHeaders, range);
    var extension = p.extension(uri.path).toLowerCase();
    if (!{'.ts', '.mp4', '.m4s', '.aac', '.vtt', '.key'}.contains(extension)) {
      extension = '.ts';
    }
    final name = '$key$extension';
    if (resources.containsKey(name)) return name;
    final lease = await fetcher.fetch(uri, policy, range: range);
    try {
      cancellation.check();
      if (bytes + lease.resource.length > maxBytes) {
        throw const FileSystemException('离线下载已达到容量上限');
      }
      reserveBytes?.call(bytes + lease.resource.length);
      await fetcher.store.pin(id, key);
      resources[name] = {'key': key};
      bytes += lease.resource.length;
      completed++;
      await onProgress(completed, completed + 1, bytes);
    } finally {
      lease.release();
    }
    return name;
  }

  Future<void> _save(String name, String text) async {
    final temporary = File(p.join(directory.path, '$name.part'));
    await temporary.writeAsString(text, flush: true);
    final target = File(p.join(directory.path, name));
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
}
