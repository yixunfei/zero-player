import 'dart:io';
import 'dart:isolate';
import '../../core/network/file_response.dart';
import '../../core/network/header_policy.dart';
import '../cache/resource_identity.dart';
import '../cache/segment_store.dart';
import '../hls/hls_manifest.dart';
import '../hls/ts_timestamps.dart';

/// Per-session metadata, with shared original bytes and separately keyed output.
final class TimestampSegments {
  final _starts = <Uri, Duration>{};
  String status = '尚未读取点播清单';
  int corrected = 0;
  int unchanged = 0;
  void clear() => _starts.clear();

  void register(HlsManifest manifest) {
    if (manifest.isMaster) return;
    if (!manifest.isComplete) {
      status = '动态清单，未改写时钟';
      return;
    }
    if (manifest.lines.any(
      (line) =>
          (line.startsWith('#EXT-X-KEY:') && !line.contains('METHOD=NONE')) ||
          line.startsWith('#EXT-X-MAP:') ||
          line.startsWith('#EXT-X-BYTERANGE:'),
    )) {
      status = '加密、fMP4 或字节区间清单，未改写时钟';
      return;
    }
    final seen = <Uri>{};
    if (manifest.segments.any((segment) => !seen.add(segment.uri))) {
      status = '重复分片地址，未改写时钟';
      return;
    }
    status = 'TS 字节校验与时间轴修正已启用';
    for (final segment in manifest.segments) {
      // Validate transport bytes, not extensions or discontinuity tags.
      _starts[segment.uri] = segment.start;
    }
  }

  Future<bool> serve(
    HttpRequest request,
    Uri uri,
    SegmentStore store,
    HeaderPolicy policy,
    Future<StoredResource> Function(String) fetch,
  ) async {
    final start = _starts[uri];
    if (start == null) return false;
    final rawKey = resourceIdentity(uri, policy.identityHeaders, null);
    final raw = await store.acquire(rawKey, () => fetch(rawKey));
    ResourceLease? normalized;
    try {
      // Unusual containers or oversized segments remain playable unchanged.
      if (raw.resource.statusCode != 200 ||
          raw.resource.length > 16 * 1024 * 1024) {
        return false;
      }
      final key = resourceIdentity(uri, {
        ...policy.identityHeaders,
        'zero-ts-clock': '2:${start.inMicroseconds}:${raw.resource.digest}',
      }, null);
      normalized = await store.acquire(key, () async {
        final file = raw.resource.file;
        final (bytes, changed) = await _normalizeFile(file.path, start);
        if (changed) {
          corrected++;
        } else {
          unchanged++;
        }
        return store.write(
          key,
          Stream.value(bytes),
          statusCode: 200,
          headers: const {'content-type': 'video/mp2t'},
          expectedLength: bytes.length,
        );
      });
      await serveLocalFile(
        request,
        normalized.resource.file,
        contentType: 'video/mp2t',
      );
      return true;
    } finally {
      normalized?.release();
      raw.release();
    }
  }
}

Future<(List<int>, bool)> _normalizeFile(String path, Duration start) =>
    Isolate.run(() async {
      final original = await File(path).readAsBytes();
      final result = normalizeTsTimestamps(original, start);
      return (result, !identical(original, result));
    });
