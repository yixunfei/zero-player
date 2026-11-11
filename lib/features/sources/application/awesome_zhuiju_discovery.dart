import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/network/cancellation_token.dart';
import '../../../core/network/network_target_policy.dart';
import '../../live/data/live_repository.dart';
import '../data/awesome_zhuiju_index.dart';
import '../data/source_repository.dart';
import '../domain/source_catalog.dart';
import 'subscription_service.dart';

final class AwesomeZhuijuCandidates {
  final videos = <SourceCandidate>[];
  final playlists = <LiveCatalogEntry>[];
  int duplicates = 0;
  int failed = 0;
}

final class AwesomeZhuijuDiscovery {
  const AwesomeZhuijuDiscovery(this.sources, this.live, this.subscriptions);
  final SourceRepository sources;
  final LiveRepository live;
  final SubscriptionService subscriptions;

  Future<AwesomeZhuijuCandidates> collect(
    AwesomeZhuijuIndex index,
    CancellationToken token,
  ) async {
    final result = AwesomeZhuijuCandidates();
    final known = await _known();
    final seen = <String>{};
    final pending = <(AwesomeResource, int)>[];
    for (final entry in index.candidates) {
      if (!_claim(entry.uri, known.roots, seen, index, result)) continue;
      if (entry.kind == AwesomeResourceKind.catalog) {
        pending.add((entry, 0));
      } else if (known.hosts.add(entry.uri.host)) {
        result.videos.add(
          SourceCandidate(
            name: entry.name,
            endpoint: entry.uri,
            kind: SourceKind.macCmsHtml,
            requestedEnabled: true,
          ),
        );
      } else {
        result.duplicates++;
      }
    }

    // Breadth first gives every listed catalog a chance before expanding children.
    for (var cursor = 0; cursor < pending.length && cursor < 50;) {
      token.check();
      final batch = pending
          .skip(cursor)
          .take((50 - cursor).clamp(0, 5))
          .toList();
      cursor += batch.length;
      final previews = await Future.wait([
        for (final (entry, _) in batch) _preview(entry.uri, token),
      ]);
      for (final (i, preview) in previews.indexed) {
        final (entry, depth) = batch[i];
        if (preview == null) {
          result.failed++;
          continue;
        }
        final label = entry.name;
        for (final source in preview.catalog.sources) {
          if (source.classification == 'adult' ||
              !_public(source.endpoint) ||
              index.blocked.contains(
                AwesomeZhuijuIndex.identity(source.endpoint),
              )) {
            continue;
          }
          if (known.videos.add(
            AwesomeZhuijuIndex.videoIdentity(source.kind.name, source.endpoint),
          )) {
            result.videos.add(source);
          } else {
            result.duplicates++;
          }
        }
        for (final playlist in preview.catalog.lives) {
          if (_claim(
            playlist.url,
            known.lives,
            known.discoveredLists,
            index,
            result,
          )) {
            result.playlists.add(
              LiveCatalogEntry(
                '追剧资源 · $label · ${playlist.name}',
                playlist.url,
                headers: playlist.headers,
                epg: playlist.epg,
              ),
            );
          }
        }
        if (depth == 2) continue;
        for (final child in preview.catalog.references) {
          if (pending.length >= 50) break;
          if (_claim(child.uri, known.roots, seen, index, result)) {
            pending.add((
              AwesomeResource(label, child.uri, AwesomeResourceKind.catalog),
              depth + 1,
            ));
          }
        }
      }
    }
    return result;
  }

  Future<CatalogPreview?> _preview(Uri uri, CancellationToken token) async {
    try {
      return await subscriptions.preview(uri, cancellation: token);
    } catch (_) {
      token.check();
      return null;
    }
  }

  bool _claim(
    Uri uri,
    Set<String> existing,
    Set<String> seen,
    AwesomeZhuijuIndex index,
    AwesomeZhuijuCandidates result,
  ) {
    final key = AwesomeZhuijuIndex.identity(uri);
    if (index.blocked.contains(key) ||
        !_public(uri) ||
        !AwesomeZhuijuIndex.durable(uri)) {
      return false;
    }
    if (!existing.contains(key) && seen.add(key)) return true;
    result.duplicates++;
    return false;
  }

  Future<
    ({
      Set<String> roots,
      Set<String> videos,
      Set<String> hosts,
      Set<String> lives,
      Set<String> discoveredLists,
    })
  >
  _known() async {
    final providers = await sources.all(includeSuppressed: true);
    final lists = await live.lists();
    final subscriptions = await sources.subscriptions();
    final builtins =
        jsonDecode(await rootBundle.loadString('assets/live_candidates.json'))
            as Map;
    final lives = {
      for (final row in lists)
        AwesomeZhuijuIndex.identity(Uri.parse(row['url'] as String)),
    };
    return (
      roots: {
        ...lives,
        for (final row in subscriptions)
          AwesomeZhuijuIndex.identity(Uri.parse(row['url'] as String)),
        for (final entry in builtins['lists'] as List)
          if (entry['origin'] is String)
            AwesomeZhuijuIndex.identity(Uri.parse(entry['origin'])),
      },
      videos: {
        for (final source in providers)
          AwesomeZhuijuIndex.videoIdentity(source.kind, source.endpoint),
      },
      hosts: {for (final source in providers) source.endpoint.host},
      lives: lives,
      discoveredLists: <String>{},
    );
  }
}

bool _public(Uri uri) {
  try {
    const NetworkTargetPolicy().validateAccess(uri, originalOrigin: false);
    return true;
  } on FormatException {
    return false;
  }
}
