import 'dart:convert';

import '../../../core/network/cancellation_token.dart';
import '../../live/data/live_repository.dart';
import '../../live/data/m3u_parser.dart';
import '../../live/domain/channel_identity.dart';
import '../../live/domain/live_channel.dart';
import '../data/awesome_zhuiju_index.dart';
import '../data/source_repository.dart';
import '../domain/source_catalog.dart';
import '../domain/video_source.dart';
import 'awesome_zhuiju_discovery.dart';
import 'awesome_zhuiju_verification.dart';

final class AwesomeZhuijuSync {
  AwesomeZhuijuSync(
    this.sources,
    this.live,
    this.discovery,
    this.verifier, {
    Future<AwesomeZhuijuIndex> Function(CancellationToken)? load,
  }) : load =
           load ??
           ((token) => AwesomeZhuijuIndex.download(verifier.network, token));

  final SourceRepository sources;
  final LiveRepository live;
  final AwesomeZhuijuDiscovery discovery;
  final AwesomeZhuijuVerification verifier;
  final Future<AwesomeZhuijuIndex> Function(CancellationToken) load;
  final _lifetime = CancellationToken();
  Future<Map<String, Object?>>? _running;
  static final url = Uri.parse(awesomeZhuijuSubscription);
  static final id = stableId(awesomeZhuijuSubscription);

  Future<Map?> lastResult() async {
    final rows = await sources.db.rows(
      'SELECT snapshot FROM subscriptions WHERE id=?',
      [id],
    );
    final snapshot = rows.firstOrNull?['snapshot'];
    if (snapshot is! String) return null;
    try {
      final report = jsonDecode(snapshot);
      return report is Map ? report : null;
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, Object?>> sync(
    CancellationToken caller, {
    void Function(String)? progress,
  }) {
    if (_running != null) throw const FormatException('源同步正在进行');
    _lifetime.check();
    final token = CancellationToken();
    final stopLifetime = _lifetime.listen(token.cancel);
    final stopCaller = caller.listen(token.cancel);
    return _running = _run(token, progress).whenComplete(() {
      stopCaller();
      stopLifetime();
      _running = null;
    });
  }

  Future<void> close() async {
    _lifetime.cancel();
    try {
      await _running;
    } catch (_) {
      // The interactive caller owns the result or cancellation.
    }
  }

  Future<Map<String, Object?>> _run(
    CancellationToken token,
    void Function(String)? progress,
  ) async {
    sources.authorize?.call();
    token.check();
    try {
      progress?.call('正在读取上游目录与检测报告');
      final index = await load(token);
      token.check();
      progress?.call('正在去重并检查直连接口');
      final candidates = await discovery.collect(index, token);
      final videos = await _verifyVideos(candidates.videos, token, progress);
      final selected = await _nextPlaylists(candidates.playlists);
      final lists = await _verifyPlaylists(selected, token, progress);
      token.check();
      progress?.call('正在保存通过验证的源');
      return _save(
        index,
        candidates,
        videos,
        lists,
        selected.lastOrNull?.url,
        token,
      );
    } catch (_) {
      token.check();
      rethrow;
    }
  }

  Future<List<SourceCandidate>> _verifyVideos(
    List<SourceCandidate> candidates,
    CancellationToken token,
    void Function(String)? progress,
  ) async {
    final verified = <SourceCandidate>[];
    var next = 0;
    var completed = 0;
    Future<void> worker() async {
      while (next < candidates.length) {
        token.check();
        final item = candidates[next++];
        if (await verifier.video(item, token)) verified.add(item);
        progress?.call('点播验证 ${++completed}/${candidates.length}');
      }
    }

    await Future.wait(
      List.generate(candidates.length.clamp(0, 4), (_) => worker()),
    );
    return verified;
  }

  Future<List<LiveCatalogEntry>> _nextPlaylists(
    List<LiveCatalogEntry> candidates,
  ) async {
    if (candidates.length <= 16) return candidates;
    final ordered = [...candidates]
      ..sort((a, b) => '${a.url}'.compareTo('${b.url}'));
    final previous = (await lastResult())?['playlistCursor'] as String?;
    final next = previous == null
        ? -1
        : ordered.indexWhere((entry) => '${entry.url}'.compareTo(previous) > 0);
    final start = next < 0 ? 0 : next;
    return [...ordered.skip(start), ...ordered.take(start)].take(16).toList();
  }

  Future<List<(LiveCatalogEntry, List<LiveChannel>)>> _verifyPlaylists(
    List<LiveCatalogEntry> candidates,
    CancellationToken token,
    void Function(String)? progress,
  ) async {
    final (names, urls) = await _liveKeys();
    final verified = <(LiveCatalogEntry, List<LiveChannel>)>[];
    for (final (i, entry) in candidates.indexed) {
      token.check();
      progress?.call('直播采样 ${i + 1}/${candidates.length} · ${entry.name}');
      try {
        final channels = await verifier.live(
          entry,
          names,
          urls,
          token,
          maxRoutes: 6,
        );
        if (channels.isNotEmpty) verified.add((entry, channels));
      } catch (_) {
        token.check();
      }
    }
    return verified;
  }

  Future<(Set<String>, Set<Uri>)> _liveKeys() async {
    final existing = await live.db.rows('SELECT name,urls FROM live_channels');
    final names = {
      for (final row in existing) channelIdentity(row['name'] as String),
    };
    final urls = {
      for (final row in existing)
        for (final uri
            in (jsonDecode(row['urls'] as String) as List).cast<String>())
          Uri.parse(uri).removeFragment(),
    };
    return (names, urls);
  }

  Future<Map<String, Object?>> _save(
    AwesomeZhuijuIndex index,
    AwesomeZhuijuCandidates candidates,
    List<SourceCandidate> videos,
    List<(LiveCatalogEntry, List<LiveChannel>)> lists,
    Uri? playlistCursor,
    CancellationToken token,
  ) => sources.db.atomic(
    () async {
      token.check();
      sources.authorize?.call();
      final existing = await sources.all(includeSuppressed: true);
      final existingProviders = {
        for (final item in existing)
          AwesomeZhuijuIndex.videoIdentity(item.kind, item.endpoint),
      };
      final hosts = {for (final item in existing) item.endpoint.host};
      final fresh = videos
          .where(
            (item) =>
                !existingProviders.contains(
                  AwesomeZhuijuIndex.videoIdentity(
                    item.kind.name,
                    item.endpoint,
                  ),
                ) &&
                (item.kind != SourceKind.macCmsHtml ||
                    !hosts.contains(item.endpoint.host)),
          )
          .toList();
      final (addedLists, addedChannels) = await _savePlaylists(lists, token);
      token.check();
      final report = <String, Object?>{
        'checkedAt': DateTime.now().toIso8601String(),
        'upstreamCheckedAt': index.checkedAt.toIso8601String(),
        'upstreamSkipped': index.skipped,
        'duplicates': candidates.duplicates,
        'catalogFailures': candidates.failed,
        'playlistCursor': playlistCursor?.toString(),
        'vodCandidates': candidates.videos.length,
        'playlistsChecked': candidates.playlists.length.clamp(0, 16),
        'playlistsDeferred': (candidates.playlists.length - 16).clamp(
          0,
          candidates.playlists.length,
        ),
        'videosAdded': fresh.length,
        'listsAdded': addedLists,
        'channelsAdded': addedChannels,
      };
      await sources.applySubscription(
        url,
        'awesome-zhuiju-free',
        jsonEncode(report),
        fresh,
        enableNew: true,
        replaceSources: false,
        deduplicateSources: false,
      );
      await sources.pauseSubscription(id, true);
      token.check();
      return report;
    },
    tables: {
      ...SourceRepository.tables,
      'live_channels',
      'live_lists',
      'app_meta',
    },
  );

  Future<(int, int)> _savePlaylists(
    List<(LiveCatalogEntry, List<LiveChannel>)> lists,
    CancellationToken token,
  ) async {
    final currentLists = {
      for (final row in await live.lists())
        AwesomeZhuijuIndex.identity(Uri.parse(row['url'] as String)),
    };
    final (names, urls) = await _liveKeys();
    var addedLists = 0;
    var addedChannels = 0;
    for (final (entry, channels) in lists) {
      token.check();
      if (!currentLists.add(AwesomeZhuijuIndex.identity(entry.url))) continue;
      final unique = <LiveChannel>[];
      for (final channel in channels) {
        final name = channelIdentity(channel.name);
        final uri = channel.urls.single.removeFragment();
        if (names.contains(name) || urls.contains(uri)) continue;
        names.add(name);
        urls.add(uri);
        unique.add(channel);
      }
      if (unique.isEmpty) continue;
      await live.importText(
        entry.name,
        entry.url,
        exportM3u(unique),
        epg: entry.epg,
        cancellation: token,
        verify: false,
        curatedRevision: 1,
        verifiedPlayback: true,
      );
      addedLists++;
      addedChannels += unique.length;
    }
    return (addedLists, addedChannels);
  }
}
