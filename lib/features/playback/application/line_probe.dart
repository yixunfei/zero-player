import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../media/network/media_probe.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/data/provider_factory.dart';

Future<ProbeResult> probeEpisode(
  AppServices services,
  CatalogItem item,
  Episode episode,
  CancellationToken token,
) async {
  if (!services.contentPolicy.itemAllowed(item)) {
    throw const FormatException('内容已屏蔽');
  }
  if (!episode.playable) throw const FormatException('此地址无法直接播放');
  final source = await services.sources.find(item.sourceId);
  token.check();
  if (source == null || !source.available) throw const FormatException('来源不可用');
  var uri = episode.uri;
  var headers = HeaderPolicy.scopedHeaders(
    source.endpoint,
    uri,
    source.headers,
  );
  if (episode.requiresResolution) {
    final media = await createVodProvider(
      source,
      services.network,
      cancellation: token,
      policy: services.contentPolicy,
    ).resolve(episode);
    uri = media.uri;
    headers = media.headers;
  }
  token.check();
  return probeMedia(
    services.http,
    uri,
    HeaderPolicy({uri: headers}),
    token,
    maxBytes: 256 * 1024,
    availabilityOnly: true,
  );
}
