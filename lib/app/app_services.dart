import '../media/content_filter/fingerprints/feature_repository.dart';
import 'dart:async';
import 'dart:io';
import '../features/supervision/application/content_policy.dart';
import '../features/supervision/application/supervision_controller.dart';
import '../features/supervision/application/installation_access.dart';
import '../features/supervision/domain/supervision_rules.dart';
import '../features/supervision/data/content_records.dart';
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
import '../core/network/cancellation_token.dart';
import '../core/network/media_http_client.dart';
import '../core/network/poster_repository.dart';
import '../core/persistence/app_database.dart';
import '../core/persistence/application_ownership.dart';
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
import '../features/live/data/live_audit_defaults.dart';
import '../features/radio/data/radio_repository.dart';
import '../features/radio/application/radio_controller.dart';
import '../features/playback/domain/player_engine.dart';
import '../media/engine/media_kit_engine.dart';
import '../features/live/data/live_health_repository.dart';
import '../features/live/application/live_probe.dart';
import '../features/live/application/channel_preflight.dart';
import '../features/live/application/builtin_live_sources.dart';
import '../features/playback/data/skip_repository.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/data/backup_service.dart';
import '../features/settings/data/lan_access_store.dart';
import '../features/sources/application/subscription_service.dart';
import '../features/sources/data/source_repository.dart';
import '../media/cache/segment_fetcher.dart';
import '../media/cache/segment_store.dart';
import '../media/export/ffmpeg_exporter.dart';
import '../media/gateway/media_gateway.dart';
import '../media/gateway/offline_server.dart';
import '../media/content_filter/content_filter_service.dart';

final servicesProvider = Provider<AppServices>(
  (ref) => throw StateError('Services not initialized'),
);

final class AppServices {
  AppServices.scoped(
    this.root,
    this.db, {
    this.radioEngine,
    PlatformServices? platform,
    this.openRequests,
    this.allowPrivateNetworks = false,
    this.channelAuditOverride,
  }) : platform = platform ?? PlatformServices();
  final bool allowPrivateNetworks;
  final LiveAuditDefaults? channelAuditOverride;
  final PlayerEngine Function()? radioEngine;
  RadioController? _radioPlayer;
  RadioController get radioPlayer => _radioPlayer ??= RadioController(
    radioEngine ?? () => MediaKitEngine(videoOutput: false, gateway: gateway),
    policy: contentPolicy,
  );
  Future<void> pauseRadioForVideo() async => _radioPlayer?.pause();
  final Stream<String>? openRequests;
  Stream<String> get localOpenRequests =>
      openRequests ?? _ownership?.channel.requests ?? const Stream.empty();
  final Directory root;

  /// In-session browsing context; distinct from the user's saved home default.
  String? searchSourceId;
  final AppDatabase db;
  final PlatformServices platform;
  late final MediaHttpClient http = MediaHttpClient(
    allowPrivateNetworks: allowPrivateNetworks,
    allowLanOrigin: lanAccess.allows,
  );
  late final lanAccess = LanAccessStore(
    db,
    authorize: () => supervision.require(SensitiveOperation.settings),
    onChanged: () => http.resetConnections(),
  );
  late final network = DocumentClient(http);
  late final posters = PosterRepository(network);
  late final SupervisionController supervision = SupervisionController(
    db,
    protectContentFilter: () => installationAccess.protectContentFilter,
  );
  late final InstallationAccess installationAccess = InstallationAccess(
    db,
    authorizeProtectionChange: () {
      if (!supervision.configured) {
        throw const FormatException('请先设置监管密码');
      }
      supervision.require(SensitiveOperation.supervision);
    },
    onProtectionChanged: supervision.invalidatePermissions,
  );
  late final settings = SettingsController(
    db,
    authorize: () => supervision.require(SensitiveOperation.settings),
    adultFilterRequired: () => supervision.enabled,
    prepareAuthorization: installationAccess.load,
    authorizeAdultDisable: installationAccess.requireAdultAccess,
    authorizeContentFilter: () =>
        supervision.require(SensitiveOperation.contentFilter),
  );
  late final contentPolicy = ContentPolicy(settings, supervision);
  void _authorizeChannels() => supervision.require(SensitiveOperation.channels);
  bool _canEnableChannels() => supervision.allows(SensitiveOperation.channels);
  late final sources = SourceRepository(
    db,
    policy: contentPolicy,
    authorize: _authorizeChannels,
    canEnable: _canEnableChannels,
  );
  late final builtins = BuiltinSources(sources);
  late final sourceProbe = SourceProbe(sources, network);
  late final sourceMonitor = BackgroundSourceMonitor(sourceProbe, settings);
  late final subscriptions = SubscriptionService(network, sources, live: live);
  late final history = HistoryRepository(db, policy: contentPolicy);
  late final skips = SkipRepository(db);
  late final filterFeatures = FeatureRepository(
    db,
    authorize: () => supervision.require(SensitiveOperation.contentFilter),
  );
  late final live = LiveRepository(
    db,
    network,
    defaults: channelAudit,
    verifyUpdates: (channels, token) => channelPreflight.refresh(
      channels.where((c) => contentPolicy.channelAllowed(c)).toList(),
      token,
    ),
    policy: contentPolicy,
    authorize: _authorizeChannels,
    canEnable: _canEnableChannels,
  );
  late final radio = RadioRepository(
    db,
    network,
    snapshotDirectory: Directory(p.join(root.path, 'radio_snapshots')),
    preflight: channelPreflight,
    policy: contentPolicy,
    authorize: _authorizeChannels,
  );
  late final liveHealth = LiveHealthRepository(
    db,
    authorize: _authorizeChannels,
    canEnable: _canEnableChannels,
  );
  late final liveProbe = LiveProbe(http, liveHealth);
  late final channelAudit = channelAuditOverride ?? LiveAuditDefaults.bundled();
  late final channelPreflight = ChannelPreflight(
    channelAudit,
    liveHealth,
    liveProbe,
  );
  late final builtinLive = BuiltinLiveSources(live);
  late final synopses = SynopsisRepository(network, db);
  late final recommendations = RecommendationRepository(network, db);
  late final backup = BackupService(
    db,
    authorize: () => supervision.require(SensitiveOperation.restore),
    authorizeExport: () => supervision.require(SensitiveOperation.export),
    authorizeAdultDisable: installationAccess.requireAdultAccess,
  );

  Future<void> restoreBackup(BackupPreview preview) async {
    await backup.restore(preview);
    contentPolicy.forgetSources();
    await sources.all(includeSuppressed: true);
    await settings.load();
    contentPolicy.refresh();
  }

  late final store = SegmentStore(
    Directory(p.join(root.path, 'segments')),
    metadata: SegmentIndex(db),
  );
  late final fetcher = SegmentFetcher(store, http);
  late final gateway = MediaGateway(store, client: http);
  late final offline = OfflineServer(store);
  late final contentFilter = ContentFilterService(
    Directory(p.join(root.path, 'content_filter')),
    http,
    isTrustedInput: (uri) =>
        gateway.isRegisteredResource(uri) || offline.isRegisteredResource(uri),
    isPlaylist: (uri) =>
        gateway.isRegisteredPlaylist(uri) || offline.isRegisteredPlaylist(uri),
  );
  late final downloads = DownloadRepository(
    db,
    Directory(p.join(root.path, 'downloads')),
    policy: contentPolicy,
  );
  late final downloadScheduler = DownloadScheduler(
    downloads,
    fetcher,
    http,
    offline,
    settings,
    isMetered: platform.isMetered,
    validateMp4: exporter.validate,
    exporter: exporter,
    resolve: (task, token) =>
        resolveDownload(task, downloads, sources, network, token),
    failover: DownloadFailover(sources, network, settings),
  );
  final exporter = FfmpegExporter();
  Future<void>? _closing;
  ApplicationOwnership? _ownership;
  static final _failedOwners = <ApplicationOwnership>[];
  StreamSubscription<void>? _sourcePolicyChanges;
  Timer? _sourcePolicyTimer;
  Future<void> _sourcePolicyRefresh = Future<void>.value();
  final _closeHooks = <Future<void> Function()>{};

  void Function() addCloseHook(Future<void> Function() hook) {
    if (_closing != null) throw StateError('Application services are closing');
    _closeHooks.add(hook);
    return () => _closeHooks.remove(hook);
  }

  static Future<AppServices> create() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final ownership = Platform.isWindows
        ? await ApplicationOwnership.acquire(directory)
        : null;
    final services = AppServices.scoped(
      directory,
      AppDatabase(File(p.join(directory.path, 'zero-player.sqlite'))),
    );
    services._ownership = ownership;
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
    await services.supervision.load();
    await services.lanAccess.load();
    await services.settings.load();
    await services.builtins.initialize();
    await services.sources.all(includeSuppressed: true);
    _sourcePolicyChanges = db
        .changesFor(const {'sources', 'source_overrides', 'source_memberships'})
        .listen((_) {
          _sourcePolicyTimer ??= Timer(const Duration(milliseconds: 100), () {
            _sourcePolicyTimer = null;
            if (_closing == null) {
              _sourcePolicyRefresh = _sourcePolicyRefresh
                  .then((_) async {
                    if (_closing == null) {
                      await sources.all(includeSuppressed: true);
                    }
                  })
                  .catchError((Object _) {});
            }
          });
        });
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

  Future<CatalogItem> detail(
    String sourceId,
    String remoteId, {
    CancellationToken? cancellation,
  }) async {
    final source = await sources.find(sourceId);
    cancellation?.check();
    if (source == null) throw const FormatException('此来源已移除，请重新搜索作品');
    final watch = Stopwatch()..start();
    try {
      final item = await createVodProvider(
        source,
        network,
        policy: contentPolicy,
        cancellation: cancellation,
      ).detail(remoteId);
      cancellation?.check();
      if (item.sourceId != sourceId || item.id != remoteId) {
        throw const FormatException('返回的影片或渠道与所选详情不一致');
      }
      await sources.health(
        sourceId,
        null,
        latencyMs: watch.elapsedMilliseconds,
      );
      await rememberContent(db, item);
      contentPolicy.requireItem(item);
      return item;
    } on RemoteFailure catch (failure) {
      cancellation?.check();
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

  Future<void> _close() async {
    try {
      await closeResources([
        () => _ownership?.channel.close(),
        () async {
          _sourcePolicyTimer?.cancel();
          await _sourcePolicyChanges?.cancel();
          await _sourcePolicyRefresh;
        },
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
        () => contentFilter.close(),
        () => offline.close(),
        () => gateway.close(),
        () => posters.close(),
        () => synopses.close(),
        () => http.close(),
        () => lanAccess.close(),
        () => platform.dispose(),
        () => contentPolicy.dispose(),
        () => settings.close(),
        () => installationAccess.close(),
        () => supervision.close(),
        () => db.close(),
      ]);
    } catch (_) {
      final ownership = _ownership;
      if (ownership != null) _failedOwners.add(ownership);
      rethrow;
    }
    await _ownership?.close();
    _ownership = null;
  }
}
