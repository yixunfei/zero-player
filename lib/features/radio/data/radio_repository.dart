import 'dart:async';
import 'dart:io';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/persistence/app_database.dart';
import '../../live/domain/live_channel.dart';
import '../../live/domain/channel_merge.dart';
import '../domain/radio_subscription.dart';
import 'radio_snapshot.dart';
import 'radio_snapshot_store.dart';
import 'radio_subscription_store.dart';

export '../domain/radio_subscription.dart';

final class RadioCatalog {
  const RadioCatalog(
    this.stations,
    this.updatedAt, {
    this.notice,
    this.needsRefresh = false,
  });
  final List<LiveChannel> stations;
  final DateTime updatedAt;
  final String? notice;
  final bool needsRefresh;
}

final class RadioRepository {
  RadioRepository(
    this.db,
    this.network, {
    Uri? source,
    Directory? snapshotDirectory,
  }) : source = source ?? Uri.parse(builtinRadioUrl),
       snapshots = RadioSnapshotStore(db, directory: snapshotDirectory);
  final AppDatabase db;
  final DocumentClient network;
  final Uri source;
  final RadioSnapshotStore snapshots;
  late final _configuration = RadioSubscriptionStore(db, source);
  final _lifetime = CancellationToken();
  final _pending = <Future<void>>{};
  final _generations = <String, int>{};
  Stream<void> get changes => db.changesFor(const {'app_meta'});

  Future<List<RadioSubscription>> subscriptions() => _configuration.read();

  Future<RadioCatalog> load({
    bool refresh = false,
    CancellationToken? cancellation,
  }) => _track(() async {
    final enabled = (await subscriptions()).where((s) => s.enabled).toList();
    final catalogs = <RadioCatalog>[];
    final notices = <String>[];
    for (final subscription in enabled) {
      _check(cancellation);
      try {
        final result = await _loadOne(subscription, refresh, cancellation);
        catalogs.add(result);
        if (result.notice != null) {
          notices.add('${subscription.name}：${result.notice}');
        }
      } catch (_) {
        _check(cancellation);
        notices.add('${subscription.name} 更新失败，暂无本地成功快照');
      }
    }
    _check(cancellation);
    if (enabled.isNotEmpty && catalogs.isEmpty) {
      throw const FormatException('广播订阅暂不可用，且没有成功快照');
    }
    final stations = catalogs.expand((c) => c.stations).toList();
    final dates = catalogs.map((c) => c.updatedAt).toList()..sort();
    return RadioCatalog(
      await withFavorites(stations),
      dates.firstOrNull ?? DateTime.now(),
      notice: notices.isEmpty ? null : notices.join('；'),
      needsRefresh: catalogs.any((c) => c.needsRefresh),
    );
  });

  Future<RadioCatalog> _loadOne(
    RadioSubscription subscription,
    bool refresh,
    CancellationToken? caller,
  ) async {
    final cached = await snapshots.read(subscription);
    _check(caller);
    if (!refresh && cached != null) return _catalog(subscription, cached);
    final token = CancellationToken();
    final unlink = _lifetime.listen(token.cancel);
    final unlinkCaller = caller?.listen(token.cancel);
    final generation = (_generations[subscription.id] ?? 0) + 1;
    _generations[subscription.id] = generation;
    try {
      final document = await network.get(
        subscription.url,
        maxBytes: 4 * 1024 * 1024,
        cancellation: token,
        networkTimeout: const Duration(seconds: 15),
      );
      final snapshot = RadioSnapshot(
        text: document.text,
        base: document.uri,
        updatedAt: DateTime.now(),
      );
      snapshot.stations(subscription);
      token.check();
      await snapshots.save(
        subscription,
        snapshot,
        cancellation: token,
        isCurrent: () => _generations[subscription.id] == generation,
      );
      token.check();
      return _catalog(subscription, snapshot);
    } catch (_) {
      token.check();
      if (cached == null) rethrow;
      return _catalog(subscription, cached, notice: '更新失败，保留上次成功列表');
    } finally {
      unlink();
      unlinkCaller?.call();
    }
  }

  RadioCatalog _catalog(
    RadioSubscription subscription,
    RadioSnapshot snapshot, {
    String? notice,
  }) => RadioCatalog(
    snapshot.stations(subscription),
    snapshot.updatedAt,
    notice: notice,
    needsRefresh:
        DateTime.now().difference(snapshot.updatedAt) >
        const Duration(hours: 24),
  );

  Future<void> saveSubscription(
    String name,
    Uri url, {
    CancellationToken? cancellation,
  }) => _track(() async {
    final normalized = url.removeFragment();
    final subscription = RadioSubscription(name: name.trim(), url: normalized);
    await _loadOne(subscription, true, cancellation);
    _check(cancellation);
    await _configuration.update((items) {
      final previous = items.where((s) => s.id == subscription.id).firstOrNull;
      return [
        for (final item in items)
          if (item.id != subscription.id) item,
        RadioSubscription(
          name: subscription.name,
          url: normalized,
          enabled: previous?.enabled ?? true,
        ),
      ];
    });
  });

  Future<void> setEnabled(String id, bool enabled) => _configuration.update(
    (items) => [
      for (final item in items)
        item.id == id
            ? RadioSubscription(
                name: item.name,
                url: item.url,
                enabled: enabled,
              )
            : item,
    ],
  );
  Future<void> removeSubscription(String id) => _configuration.update(
    (items) => items.where((item) => item.id != id).toList(),
  );
  Future<RadioCatalog> refreshSubscription(
    RadioSubscription subscription, {
    CancellationToken? cancellation,
  }) => _track(() => _loadOne(subscription, true, cancellation));

  Future<List<LiveChannel>> withFavorites(List<LiveChannel> stations) async {
    final rows = await db.rows(
      "SELECT key FROM app_meta WHERE key GLOB 'radio_favorite:*' AND value='true'",
    );
    final ids = rows
        .map(
          (row) => (row['key'] as String).substring('radio_favorite:'.length),
        )
        .toSet();
    return mergeChannelAliases([
      for (final station in stations)
        for (final entry in station.entries)
          entry.withFavorite(ids.contains(entry.id)),
    ]);
  }

  Future<void> favorite(LiveChannel station, bool value) => db.atomic(() async {
    for (final id in station.preferenceIds) {
      await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
        'radio_favorite:$id',
        value ? 'true' : 'false',
      ]);
    }
  }, tables: const {'app_meta'});

  void _check(CancellationToken? token) {
    _lifetime.check();
    token?.check();
  }

  Future<T> _track<T>(Future<T> Function() action) async {
    _lifetime.check();
    final done = Completer<void>();
    _pending.add(done.future);
    try {
      return await action();
    } finally {
      done.complete();
      _pending.remove(done.future);
    }
  }

  Future<void> close() async {
    _lifetime.cancel();
    await Future.wait(_pending.toList());
    await snapshots.close();
  }
}
