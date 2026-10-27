import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/request_scheduler.dart';
import '../../sources/domain/video_source.dart';

final class WebsiteTransport {
  const WebsiteTransport(
    this.source,
    this.network, {
    this.cancellation,
    this.priority = RequestPriority.interactive,
    this.onActivity,
  });
  final VideoSource source;
  final DocumentClient network;
  final CancellationToken? cancellation;
  final RequestPriority priority;
  final void Function(bool)? onActivity;
  Uri url(String path) => source.endpoint.resolve(path);

  Future<Document> get(Uri uri, {Map<String, String> headers = const {}}) =>
      network.get(
        uri,
        headers: {...source.headers, ...headers},
        cancellation: cancellation,
        priority: priority,
        onActivity: onActivity,
        maxBytes: 4 * 1024 * 1024,
      );

  void requireSameOrigin(Uri uri) {
    if (uri.origin != source.endpoint.origin || uri.userInfo.isNotEmpty) {
      throw const RemoteFailure(FailureKind.invalid, '解析地址不属于当前渠道');
    }
  }
}
