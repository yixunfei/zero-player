import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/platform/close_resources.dart';
import '../features/discovery/data/synopsis_repository.dart';
import '../features/sources/application/builtin_sources.dart';
import '../features/sources/application/background_source_monitor.dart';
import '../features/sources/application/source_probe.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/document_client.dart';
import '../core/network/media_http_client.dart';
import '../core/network/poster_repository.dart';
import '../core/persistence/app_database.dart';
import '../core/persistence/segment_index.dart';
import '../core/platform/platform_services.dart';
import '../features/catalog/data/provider_factory.dart';
import '../features/catalog/domain/catalog_item.dart';
import '../features/discovery/data/recommendation_repository.dart';
import '../features/downloads/application/download_scheduler.dart';
import '../features/downloads/application/download_resolver.dart';
import '../features/downloads/application/download_failover.dart';
import '../features/downloads/data/download_repository.dart';
import '../features/library/data/history_repository.dart';
import '../features/live/data/live_repository.dart';
import '../features/radio/data/radio_repository.dart';
import '../features/radio/application/radio_controller.dart';
import '../features/playback/domain/player_engine.dart';
import '../media/engine/media_kit_engine.dart';
import '../features/live/data/live_health_repository.dart';
import '../features/live/application/live_probe.dart';
import '../features/live/application/builtin_live_sources.dart';
import '../features/playback/data/skip_repository.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/data/backup_service.dart';
import '../features/sources/application/subscription_service.dart';
import '../features/sources/data/source_repository.dart';
import '../media/cache/segment_fetcher.dart';
import '../media/cache/segment_store.dart';
import '../media/export/ffmpeg_exporter.dart';
import '../media/gateway/media_gateway.dart';
import '../media/gateway/offline_server.dart';

final servicesProvider = Provider<AppServices>(
  (ref) => throw StateError('Services not initialized'),
);

final class AppServices {
  AppServices.scoped(
    this.root,
    this.db, {
    this.radioEngine,
    bool allowPrivateNetworks = false,
  }) : http = MediaHttpClient(allowPrivateNetworks: allowPrivateNetworks);
  final PlayerEngine Function()? radioEngine;
  RadioController? _radioPlayer;
  RadioController get radioPlayer => _radioPlayer ??= RadioController(
    radioEngine ?? () => MediaKitEngine(videoOutput: false, gateway: gateway),
  );
  Future<void> pauseRadioForVideo() async => _radioPlayer?.pause();
  final Directory root;
  final AppDatabase db;
  final platform = PlatformServices();
  final MediaHttpClient http;
  late final network = DocumentClient(http);
  late final posters = PosterRepository(network);
  late final settings = SettingsController(db);
  late final sources = SourceRepository(db);
  late final builtins = BuiltinSources(sources);
  late final sourceProbe = SourceProbe(sources, network);
  late final sourceMonitor = BackgroundSourceMonitor(sourceProbe, settings);
  late final subscriptions = SubscriptionService(network, sources);
  late final history = HistoryRepository(db);
  late final skips = SkipRepository(db);
  late final live = LiveRepository(db, network);
  late final radio = RadioRepository(
    db,
    network,
    snapshotDirectory: Directory(p.join(root.path, 'radio_snapshots')),
  );
  late final liveHealth = LiveHealthRepository(db);
  late final liveProbe = LiveProbe(http, liveHealth);
  late final builtinLive = BuiltinLiveSources(live);
  late final synopses = SynopsisRepository(network, db);
  late final recommendations = RecommendationRepository(network, db);
  late final backup = BackupService(db);
  late final store = SegmentStore(
    Directory(p.join(root.path, 'segments')),
    metadata: SegmentIndex(db),
  );
  late final fetcher = SegmentFetcher(store, http);
  late final gateway = MediaGateway(store, client: http);
  late final offline = OfflineServer(store);
  late final downloads = DownloadRepository(
    db,
    Directory(p.join(root.path, 'downloads')),
  );
  late final downloadScheduler = DownloadScheduler(
    downloads,
    fetcher,
    http,
    offline,
    settings,
    isMetered: platform.isMetered,
    validateMp4: exporter.validate,
    resolve: (task, token) =>
        resolveDownload(task, downloads, sources, network, token),
    failover: DownloadFailover(sources, network, settings),
  );
  final exporter = FfmpegExporter();
  Future<void>? _closing;
  final _closeHooks = <Future<void> Function()>{};

  void Function() addCloseHook(Future<void> Function() hook) {
    if (_closing != null) throw StateError('Application services are closing');
    _closeHooks.add(hook);
    return () => _closeHooks.remove(hook);
  }

  static Future<AppServices> create() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final services = AppServices.scoped(
      directory,
      AppDatabase(File(p.join(directory.path, 'zero-player.sqlite'))),
    );
    try {
      await services._initialize();
      return services;
    } catch (_) {
      try {
        await services.close();
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'startup cleanup',
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _initialize() async {
    final services = this;
    await services.builtins.initialize();
    await services.settings.load();
    await services.builtinLive.initialize();
    await services.store.initialize();
    await services.platform.initialize(
      windowState: File(p.join(root.path, 'window.json')),
    );
    services.platform.desktop?.shutdown = services.close;
    await services.platform.enableRadioTray(services.radioPlayer);
    await services.gateway.start();
    await services.downloadScheduler.initialize();
    services.settings.addListener(services._applySettings);
    services._applySettings();
  }

  void _applySettings() =>
      store.maxBytes = settings.value.cacheMiB * 1024 * 1024;

  Future<CatalogItem> detail(String sourceId, String remoteId) async {
    final source = await sources.find(sourceId);
    if (source == null) throw const FormatException('此来源已移除，请重新搜索作品');
    final watch = Stopwatch()..start();
    try {
      final item = await createVodProvider(source, network).detail(remoteId);
      await sources.health(
        sourceId,
        null,
        latencyMs: watch.elapsedMilliseconds,
      );
      return item;
    } on RemoteFailure catch (failure) {
      await sources.health(sourceId, failure);
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> closeSafely() async {
    try {
      await close().timeout(const Duration(seconds: 10));
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'application shutdown',
        ),
      );
    }
  }

  Future<void> _close() => closeResources([
    () async {
      await platform.radioTray?.dispose();
    },
    () async {
      await _radioPlayer?.close();
    },
    () => radio.close(),
    ..._closeHooks,
    () => _closeHooks.clear(),
    () => subscriptions.close(),
    () => builtinLive.close(),
    () => liveProbe.close(),
    () => downloadScheduler.close(),
    () => sourceMonitor.close(),
    () => settings.removeListener(_applySettings),
    () => offline.close(),
    () => gateway.close(),
    () => posters.close(),
    () => synopses.close(),
    () => http.close(),
    () => platform.dispose(),
    () => settings.close(),
    () => db.close(),
  ]);
}
