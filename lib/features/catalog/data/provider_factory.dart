import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/request_scheduler.dart';
import '../../sources/domain/video_source.dart';
import '../domain/vod_provider.dart';
import 'cms_provider.dart';
import 'kanju_provider.dart';
import 'mac_cms_html_provider.dart';
import 'website_transport.dart';
import '../../supervision/application/content_policy.dart';
import '../../supervision/data/filtering_vod_provider.dart';

VodProvider createVodProvider(
  VideoSource source,
  DocumentClient network, {
  CancellationToken? cancellation,
  RequestPriority priority = RequestPriority.interactive,
  void Function(bool)? onActivity,
  ContentPolicy? policy,
}) {
  final transport = WebsiteTransport(
    source,
    network,
    cancellation: cancellation,
    priority: priority,
    onActivity: onActivity,
  );
  final provider = switch (source.kind) {
    'kanju' => KanjuProvider(transport),
    'macCmsHtml' => MacCmsHtmlProvider(transport),
    'cms' => CmsProvider(
      source,
      network,
      cancellation: cancellation,
      priority: priority,
      onActivity: onActivity,
    ),
    _ => throw const RemoteFailure(FailureKind.unsupported, '不支持的点播来源类型'),
  };
  return policy == null
      ? provider
      : FilteringVodProvider(provider, source, policy);
}
