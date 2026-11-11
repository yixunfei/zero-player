import 'dart:async';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/header_policy.dart';
import '../../../core/network/network_target_policy.dart';
import '../../../media/network/media_probe.dart';
import '../../catalog/data/provider_factory.dart';
import '../../live/data/live_playlist_parser.dart';
import '../../live/data/playlist_channels.dart';
import '../../live/domain/channel_identity.dart';
import '../../live/domain/live_channel.dart';
import '../../supervision/application/content_policy.dart';
import '../../supervision/domain/content_classification.dart';
import '../domain/source_catalog.dart';
import '../data/awesome_zhuiju_index.dart';
import '../domain/video_source.dart';

typedef DecodeVideoSample =
    Future<bool> Function(Uri, Map<String, String>, CancellationToken);

final class AwesomeZhuijuVerification {
  const AwesomeZhuijuVerification(this.network, this.decode, {this.policy});
  final DocumentClient network;
  final DecodeVideoSample decode;
  final ContentPolicy? policy;

  Future<bool> video(SourceCandidate item, CancellationToken caller) async {
    final token = CancellationToken();
    final unlink = caller.listen(token.cancel);
    final deadline = Timer(const Duration(minutes: 2), token.cancel);
    final source = VideoSource(
      id: stableId('\${item.kind.name}|\${item.endpoint}'),
      name: item.name,
      endpoint: item.endpoint,
      kind: item.kind.name,
      classification: item.classification,
    );
    try {
      final provider = createVodProvider(
        source,
        network,
        cancellation: token,
        policy: policy,
      );
      final catalog = await provider.browse();
      if (catalog.categories.values.any(
        (name) => adultContent(name, category: true),
      )) {
        return false;
      }
      final tested = <Uri>{};
      var playable = 0;
      for (final item in catalog.page.items.take(4)) {
        token.check();
        if (adultContent(item.title) ||
            adultContent(item.category, category: true)) {
          continue;
        }
        try {
          final detail = await provider.detail(item.id);
          if (adultContent(detail.title) ||
              adultContent(detail.category, category: true)) {
            continue;
          }
          for (final episode
              in detail.lines
                  .expand((line) => line.episodes)
                  .where((episode) => episode.playable)
                  .take(2)) {
            final media = await provider.resolve(episode);
            if (!tested.add(media.uri)) continue;
            if (await _check(media.uri, media.headers, token)) {
              if (++playable == 2) return true;
              break;
            }
          }
        } catch (_) {
          token.check();
        }
      }
      return false;
    } catch (_) {
      caller.check();
      return false;
    } finally {
      deadline.cancel();
      unlink();
      token.cancel();
    }
  }

  Future<List<LiveChannel>> live(
    LiveCatalogEntry entry,
    Set<String> knownNames,
    Set<Uri> knownUrls,
    CancellationToken token, {
    required int maxRoutes,
  }) async {
    if (policy?.textAllowed(entry.name) == false) return [];
    final document = await network.get(
      entry.url,
      headers: entry.headers,
      cancellation: token,
      maxBytes: 8 * 1024 * 1024,
      networkTimeout: const Duration(seconds: 10),
    );
    final id = stableId('\${entry.url}');
    final channels = preparePlaylistChannels(
      parseLivePlaylist(document.text, document.uri, id),
      const [],
      entry.headers,
    );
    final result = <LiveChannel>[];
    final tested = <Uri>{...knownUrls};
    var tried = 0;
    for (final channel in channels) {
      if (tried >= maxRoutes) break;
      token.check();
      final identity = channelIdentity(channel.name);
      if (knownNames.contains(identity) ||
          adultContent(channel.name) ||
          adultContent(channel.group, category: true) ||
          policy?.channelAllowed(channel) == false) {
        continue;
      }
      for (final uri in channel.urls.take(2)) {
        if (tried >= maxRoutes) break;
        if (uri.path.toLowerCase().endsWith('.mp4') ||
            !AwesomeZhuijuIndex.durable(uri) ||
            !tested.add(uri.removeFragment())) {
          continue;
        }
        tried++;
        final scoped = HeaderPolicy.playlistHeaders(
          entry.url,
          uri,
          channel.headers,
        );
        final headers = {
          for (final header in scoped.entries)
            if ({
              'user-agent',
              'referer',
              'origin',
            }.contains(header.key.toLowerCase()))
              header.key: header.value.trim(),
        };
        if (!await _check(uri, headers, token, repeat: true)) continue;
        knownNames.add(identity);
        knownUrls.add(uri.removeFragment());
        result.add(
          LiveChannel(
            id: channel.id,
            listId: id,
            name: channel.name,
            group: channel.group,
            tvgId: channel.tvgId,
            logo: channel.logo,
            urls: [uri],
            headerOrigin: entry.url,
            headers: headers,
            listName: entry.name,
            metadata: channel.metadata,
          ),
        );
        break;
      }
    }
    return result;
  }

  Future<bool> _check(
    Uri uri,
    Map<String, String> headers,
    CancellationToken token, {
    bool repeat = false,
  }) async {
    try {
      const NetworkTargetPolicy().validateAccess(uri, originalOrigin: false);
      await probeMedia(
        network.http,
        uri,
        HeaderPolicy({uri: headers}),
        token,
        maxBytes: 128 * 1024,
        availabilityOnly: true,
        networkTimeout: const Duration(seconds: 6),
      );
      if (!await decode(uri, headers, token)) return false;
      return !repeat || await decode(uri, headers, token);
    } catch (_) {
      token.check();
      return false;
    }
  }
}
