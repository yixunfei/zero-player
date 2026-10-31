import 'dart:io';
import '../../core/network/cancellation_token.dart';
import '../../core/network/header_policy.dart';
import '../../core/network/media_http_client.dart';
import '../../core/network/request_scheduler.dart';
import 'resource_identity.dart';
import 'segment_store.dart';

final class SegmentFetcher {
  const SegmentFetcher(this.store, this.http);
  final SegmentStore store;
  final MediaHttpClient http;

  Future<ResourceLease> fetch(
    Uri uri,
    HeaderPolicy policy, {
    String? range,
    bool verify = false,
    String? cachePartition,
    CancellationToken? cancellation,
    RequestPriority priority = RequestPriority.background,
  }) {
    if (cancellation != null && cachePartition == null) {
      throw ArgumentError('Cancellation requires a task-owned cache partition');
    }
    http.targetPolicy.validateAccess(
      uri,
      originalOrigin: policy.containsOrigin(uri),
    );
    final key = resourceIdentity(uri, {
      ...policy.identityHeaders,
      'zero-player-cache-partition': ?cachePartition,
    }, range);
    return store.acquire(key, () async {
      final payload = await http.open(
        uri,
        policy: policy,
        range: range,
        priority: priority,
        cancellation: cancellation,
      );
      final response = payload.response;
      if (response.statusCode != 200 && response.statusCode != 206) {
        await payload.body.take(0).drain<void>();
        throw const HttpException('媒体分片不可用');
      }
      if (range != null && response.statusCode != 206) {
        await payload.body.take(0).drain<void>();
        throw const HttpException('来源不支持请求的字节范围');
      }
      final headers = <String, String>{};
      for (final name in ['content-type', 'content-range', 'accept-ranges']) {
        final value = response.headers.value(name);
        if (value != null) headers[name] = value;
      }
      return store.write(
        key,
        payload.body,
        statusCode: response.statusCode,
        headers: headers,
        expectedLength: response.contentLength < 0
            ? null
            : response.contentLength,
      );
    }, verify: verify);
  }
}
