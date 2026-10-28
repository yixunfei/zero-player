import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
  final _pinned = <String, int>{};
  String _revision = '';
  String _root = '';
  int _revisionBytes = 0;
  int bytes = 0;
  int completed = 0;

  Future<String> run(Uri uri) async {
    _pinned
      ..clear()
      ..addAll(await fetcher.store.pinnedResources(id));
    bytes = _pinned.values.fold(0, (sum, length) => sum + length);
    await _loadCheckpoint(uri);
    // Persist actual retained disk usage before the first network request, so a
    // failed or interrupted restart cannot hide old revisions from the quota.
    await onProgress(0, 0, bytes);
    _reserve(bytes);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _run(uri);
      } on _ManifestChanged {
        if (attempt == 1) {
          throw const FormatException('媒体清单持续变化，请稍后重试下载');
        }
        // A signature may identify a different payload. Restart into a new
        // cache partition instead of stripping query parameters or mixing bytes.
        _newRevision(uri);
        await _saveCheckpoint();
      }
    }
    throw StateError('Unreachable download state');
  }

  Future<void> _loadCheckpoint(Uri uri) async {
    final checkpoint = File(p.join(directory.path, 'checkpoints.json'));
    _newRevision(uri);
    if (await checkpoint.exists()) {
      try {
        final saved = jsonDecode(await checkpoint.readAsString());
        if (saved is Map &&
            saved['root'] == uri.toString() &&
            saved['revision'] is String &&
            RegExp(
              r'^[a-zA-Z0-9_-]{32}$',
            ).hasMatch(saved['revision'] as String) &&
            saved['manifests'] is Map) {
          _fingerprints.addAll(Map<String, String>.from(saved['manifests']));
          _revision = saved['revision'] as String;
        }
      } on FormatException {
        // Incomplete checkpoint: start an isolated revision, never trust bytes.
      } on TypeError {
        _fingerprints.clear();
      }
    }
    await _saveCheckpoint();
  }

  void _newRevision(Uri uri) {
    _root = uri.toString();
    final random = Random.secure();
    _revision = base64Url.encode(List.generate(24, (_) => random.nextInt(256)));
    _fingerprints.clear();
    _visited.clear();
    _active.clear();
    resources.clear();
    completed = 0;
    _revisionBytes = 0;
  }

  Future<void> _saveCheckpoint() => _save(
    'checkpoints.json',
    jsonEncode({
      'root': _root,
      'revision': _revision,
      'manifests': _fingerprints,
    }),
  );

  Future<String> _run(Uri uri) async {
    final root = await _manifest(uri, 0);
    cancellation.check();
    for (final value in resources.values) {
      if (value['key'] != null) await fetcher.store.verify(value['key']!);
    }
    await _save('resources.json', jsonEncode(resources));
    final currentKeys = resources.values
        .map((v) => v['key'])
        .whereType<String>()
        .toSet();
    await fetcher.store.retainPins(id, currentKeys);
    _pinned.removeWhere((key, _) => !currentKeys.contains(key));
    bytes = _revisionBytes;
    await onProgress(completed, completed, bytes);
    return root;
  }

  Future<String> _manifest(
    Uri uri,
    int depth, {
    Map<String, String> variables = const {},
  }) async {
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
      throw const _ManifestChanged();
    }
    _fingerprints[uri.toString()] = fingerprint;
    await _saveCheckpoint();
    var manifest = HlsManifest.parse(text, payload.uri, variables: variables);
    if (!manifest.isMaster && !manifest.isComplete) {
      throw const FormatException('动态直播清单不支持整集离线下载');
    }
    manifest = selectOfflineVariant(manifest);
    final name = '${stableId('$_revision|$uri')}.m3u8';
    _visited[uri] = name;
    _active.add(uri);
    final output = await rewriteOffline(manifest, (
      resource, {
      range,
      playlist = false,
    }) async {
      cancellation.check();
      if (playlist) {
        return Uri(
          path: await _manifest(
            resource,
            depth + 1,
            variables: manifest.variables,
          ),
        );
      }
      return Uri(path: await _segment(resource, range));
    });
    await _save(name, output);
    resources[name] = {'local': name, 'digest': stableId(output)};
    _active.remove(uri);
    return name;
  }

  Future<String> _segment(Uri uri, String? range) async {
    final key = resourceIdentity(uri, {
      ...policy.identityHeaders,
      'zero-player-cache-partition': _revision,
    }, range);
    var extension = p.extension(uri.path).toLowerCase();
    if (!{'.ts', '.mp4', '.m4s', '.aac', '.vtt', '.key'}.contains(extension)) {
      extension = '.ts';
    }
    final name = '$key$extension';
    if (resources.containsKey(name)) return name;
    final lease = await fetcher.fetch(
      uri,
      policy,
      range: range,
      verify: true,
      cachePartition: _revision,
      cancellation: cancellation,
    );
    try {
      cancellation.check();
      final length = lease.resource.length;
      final ownedBytes = bytes - (_pinned[key] ?? 0) + length;
      _reserve(ownedBytes);
      await fetcher.store.pin(id, key);
      _pinned[key] = length;
      resources[name] = {'key': key};
      bytes = ownedBytes;
      _revisionBytes += length;
      completed++;
      // Nested rendition playlists are discovered lazily; the total is unknown
      // until every manifest has been visited, not completed + 1.
      await onProgress(completed, 0, bytes);
    } finally {
      lease.release();
    }
    return name;
  }

  void _reserve(int ownedBytes) {
    try {
      if (ownedBytes > maxBytes) throw const FileSystemException('离线下载已达到容量上限');
      reserveBytes?.call(ownedBytes);
    } on FileSystemException {
      if (_pinned.isEmpty) rethrow;
      throw const FileSystemException('安全重下需额外空间，可删除旧任务后重建或增加容量');
    }
  }

  Future<void> _save(String name, String text) async {
    final temporary = File(p.join(directory.path, '$name.part'));
    await temporary.writeAsString(text, flush: true);
    final target = File(p.join(directory.path, name));
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
}

final class _ManifestChanged implements Exception {
  const _ManifestChanged();
}
