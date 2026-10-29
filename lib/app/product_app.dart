import 'dart:async';
import '../features/supervision/presentation/supervision_page.dart';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/catalog/presentation/detail_page.dart';
import '../features/discovery/presentation/discovery_page.dart';
import '../features/discovery/presentation/release_calendar_page.dart';
import '../features/downloads/presentation/downloads_page.dart';
import '../features/library/presentation/history_page.dart';
import '../features/live/presentation/live_page.dart';
import '../features/radio/presentation/radio_page.dart';
import '../features/playback/application/playback_controller.dart';
import '../features/playback/presentation/player_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/sources/presentation/sources_page.dart';
import 'app_services.dart';
import 'shell.dart';
import 'app_theme.dart';
import 'application_fullscreen.dart';
import 'list_keyboard_navigation.dart';
import 'app_back_dispatcher.dart';
import 'app_layout.dart';

final class ProductApp extends ConsumerStatefulWidget {
  const ProductApp({super.key});
  @override
  ConsumerState<ProductApp> createState() => _ProductAppState();
}

final class _ProductAppState extends ConsumerState<ProductApp>
    with WidgetsBindingObserver {
  late final AppServices services;
  late final GoRouter router;
  late final AppBackDispatcher backDispatcher;
  @override
  void initState() {
    super.initState();
    services = ref.read(servicesProvider);
    PaintingBinding.instance.imageCache
      ..maximumSize = 120
      ..maximumSizeBytes = 64 * 1024 * 1024;
    WidgetsBinding.instance.addObserver(this);
    router = _createRouter();
    backDispatcher = AppBackDispatcher(
      router: router,
      platform: services.platform,
      shutdown: services.closeSafely,
    );
    unawaited(services.subscriptions.refreshDue());
    services.sourceMonitor.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && services.settings.value.startFullscreen) {
        unawaited(_startFullscreen());
      }
    });
  }

  GoRouter _createRouter() => GoRouter(
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(
          services: services,
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, state) => DiscoveryPage(services: services),
          ),
          GoRoute(
            path: '/search',
            builder: (_, state) => PageListNavigation(
              child: SearchPage(
                services: services,
                initial: state.uri.queryParameters['q'] ?? '',
                preferredSourceId:
                    state.uri.queryParameters['source'] ??
                    services.searchSourceId,
              ),
            ),
          ),
          GoRoute(
            path: '/live',
            builder: (_, state) => LivePage(services: services),
          ),
          GoRoute(
            path: '/radio',
            builder: (_, state) => RadioPage(services: services),
          ),
          GoRoute(
            path: '/calendar',
            builder: (_, _) => ReleaseCalendarPage(services: services),
          ),
          GoRoute(
            path: '/history',
            builder: (_, state) =>
                PageListNavigation(child: HistoryPage(services: services)),
          ),
          GoRoute(
            path: '/downloads',
            builder: (_, state) =>
                PageListNavigation(child: DownloadsPage(services: services)),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, state) =>
                PageListNavigation(child: SettingsPage(services: services)),
          ),
        ],
      ),
      GoRoute(
        path: '/supervision',
        builder: (_, state) => SupervisionPage(services: services),
      ),
      GoRoute(
        path: '/sources',
        builder: (_, state) =>
            PageListNavigation(child: SourcesPage(services: services)),
      ),
      GoRoute(
        path: '/detail/:source/:id',
        builder: (_, state) => DetailPage(
          services: services,
          sourceId: state.pathParameters['source']!,
          remoteId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/player',
        redirect: (_, state) => state.extra is PlaybackRequest ? null : '/',
        builder: (_, state) => PlayerPage(
          services: services,
          request: state.extra! as PlaybackRequest,
        ),
      ),
    ],
  );

  Future<void> _startFullscreen() async {
    try {
      await services.platform.setAppFullscreen(true);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'application fullscreen',
          context: ErrorDescription('while entering startup fullscreen'),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(services.closeSafely());
      return;
    }
    unawaited(
      services.downloadScheduler.setForeground(
        state == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  Future<AppExitResponse> didRequestAppExit() =>
      services.platform.requestAppExit(services.closeSafely);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.settings,
    builder: (context, _) {
      final tv =
          services.platform.television ||
          (services.settings.value.mode == 'television' &&
              !usesCompactNavigation(context, services.platform));
      return MaterialApp.router(
        title: 'Zero Player',
        debugShowCheckedModeBanner: false,
        routerDelegate: router.routerDelegate,
        routeInformationParser: router.routeInformationParser,
        routeInformationProvider: router.routeInformationProvider,
        backButtonDispatcher: backDispatcher,
        onNavigationNotification: (notification) {
          // Root exit requires confirmation even when nested navigators cannot pop.
          unawaited(
            SystemNavigator.setFrameworkHandlesBack(
              services.platform.android || notification.canHandlePop,
            ),
          );
          return true;
        },
        theme: buildAppTheme(
          Brightness.light,
          tv,
          services.settings.value.theme,
          font: services.settings.value.font,
        ),
        darkTheme: buildAppTheme(
          Brightness.dark,
          tv,
          services.settings.value.theme,
          font: services.settings.value.font,
        ),
        builder: (context, child) =>
            ApplicationFullscreen(platform: services.platform, child: child!),
        themeMode: switch (services.settings.value.theme) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        },
      );
    },
  );
}
