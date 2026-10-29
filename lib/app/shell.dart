import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import 'app_services.dart';
import 'application_fullscreen.dart';
import 'app_layout.dart';
import 'mobile_bottom_navigation.dart';
import 'navigation_guide.dart';
import '../features/radio/presentation/radio_mini_player.dart';

const _destinations = [
  ('/', '发现', Icons.explore_outlined),
  ('/search', '搜索', Icons.search),
  ('/live', '直播', Icons.live_tv),
  ('/radio', '广播（实验）', Icons.radio_outlined),
  ('/history', '记录', Icons.history),
  ('/downloads', '下载', Icons.download_outlined),
  ('/settings', '设置', Icons.settings_outlined),
];

final class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.services,
    required this.location,
    required this.child,
  });
  final AppServices services;
  final String location;
  final Widget child;
  @override
  State<AppShell> createState() => _AppShellState();
}

final class _AppShellState extends State<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _focus = FocusNode();
  Timer? _hoverTimer;
  bool _hoverOpened = false;
  bool _barVisible = true;
  int get _index => _destinations
      .indexWhere((d) => d.$1 == widget.location)
      .clamp(0, _destinations.length - 1);
  @override
  void initState() {
    super.initState();
    widget.services.platform.appFullscreen.addListener(_fullscreenChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.services.settings.value.navigationGuideSeen) {
        unawaited(
          showNavigationGuide(
            context,
            widget.services.settings,
            platform: widget.services.platform,
          ),
        );
      }
    });
  }

  void _fullscreenChanged() {
    _hoverTimer?.cancel();
    _hoverOpened = false;
    setState(() => _barVisible = true);
    _scaffold.currentState?.closeDrawer();
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _focus.dispose();
    widget.services.platform.appFullscreen.removeListener(_fullscreenChanged);
    super.dispose();
  }

  void _open({bool hover = false}) {
    setState(() => _barVisible = true);
    _hoverOpened = hover;
    _scaffold.currentState?.openDrawer();
  }

  void _navigate(int index) {
    _scaffold.currentState?.closeDrawer();
    context.go(_destinations[index].$1);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.services.platform.appFullscreen,
    builder: (context, full, _) {
      final wide = !usesCompactNavigation(context, widget.services.platform);
      return _appFrame(full: full, wide: wide);
    },
  );

  Widget _appFrame({required bool full, required bool wide}) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): _open,
        const SingleActivator(LogicalKeyboardKey.contextMenu): _open,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          if (widget.location != '/search') context.push('/search');
        },
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Scaffold(
          key: _scaffold,
          drawer: _drawer(),
          body: SafeArea(
            child: Column(
              children: [
                ClipRect(
                  child: AnimatedAlign(
                    alignment: Alignment.topCenter,
                    heightFactor: _barVisible ? 1 : 0,
                    duration: _animationDuration(context),
                    child: ExcludeFocus(
                      excluding: !_barVisible,
                      child: _appBar(wide),
                    ),
                  ),
                ),
                _pageBody(wide),
                if (widget.location != '/radio')
                  RadioMiniPlayer(controller: widget.services.radioPlayer),
              ],
            ),
          ),
          bottomNavigationBar: _navigationBar(full: full, wide: wide),
        ),
      ),
    );
  }

  Duration _animationDuration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 180);

  Widget? _navigationBar({required bool full, required bool wide}) {
    if (wide || MediaQuery.viewInsetsOf(context).bottom > 0) return null;
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.topCenter,
        heightFactor: _barVisible ? 1 : 0,
        duration: _animationDuration(context),
        child: IgnorePointer(
          ignoring: !_barVisible,
          child: ExcludeSemantics(
            excluding: !_barVisible,
            child: ExcludeFocus(
              excluding: !_barVisible,
              child: MobileBottomNavigation(
                location: widget.location,
                onNavigate: (route) => context.go(route),
                onMore: _open,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageBody(bool wide) => Expanded(
    child: NotificationListener<ScrollUpdateNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          Positioned.fill(child: FocusTraversalGroup(child: widget.child)),
          if (wide && !_barVisible)
            Positioned(
              left: 12,
              top: 8,
              child: IconButton.filled(
                tooltip: '展开导航',
                onPressed: _open,
                icon: const Icon(Icons.menu),
              ),
            ),
          if (wide)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 10,
              child: MouseRegion(
                onEnter: (_) {
                  _hoverTimer?.cancel();
                  _hoverTimer = Timer(
                    const Duration(milliseconds: 250),
                    () => _open(hover: true),
                  );
                },
                onExit: (_) => _hoverTimer?.cancel(),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    ),
  );

  bool _onScroll(ScrollUpdateNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    final scrollingUp =
        delta < -2 &&
        (notification.dragDetails != null ||
            (notification.context != null &&
                Scrollable.maybeOf(
                      notification.context!,
                    )?.position.userScrollDirection ==
                    ScrollDirection.forward));
    // Lazy layout can correct pixels backwards at End/resize. That is not an
    // upward gesture and must not reopen the bar and change the extent again.
    final visible = notification.metrics.pixels <= 24 || scrollingUp
        ? true
        : delta > 2
        ? false
        : _barVisible;
    if (visible != _barVisible) setState(() => _barVisible = visible);
    return false;
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _barVisible = true;
  }

  PreferredSizeWidget _appBar(bool wide) => AppBar(
    primary: false,
    leadingWidth: wide ? 108 : 56,
    leading: wide
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
            child: Tooltip(
              message: '展开导航 (Ctrl+M)',
              child: FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.menu, size: 20),
                label: const Text('菜单'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          )
        : IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            tooltip: '展开导航 (Ctrl+M)',
            onPressed: _open,
            icon: const Icon(Icons.menu),
          ),
    title: Text(
      wide
          ? 'ZERO PLAYER  /  ${_destinations[_index].$2}'
          : _destinations[_index].$2,
    ),
    actions: [
      if (wide) AppFullscreenButton(platform: widget.services.platform),
      IconButton(
        tooltip: '管理视频源',
        onPressed: () => context.push('/sources'),
        icon: const Icon(Icons.dns_outlined),
      ),
    ],
  );

  Widget _drawer() => MouseRegion(
    onExit: (_) {
      if (_hoverOpened) _scaffold.currentState?.closeDrawer();
    },
    child: Drawer(
      width: 280,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/brand/logo.jpg',
                  width: 44,
                  height: 44,
                ),
              ),
              title: const Text('ZERO PLAYER'),
              trailing: IconButton(
                tooltip: '收起导航',
                onPressed: () => _scaffold.currentState?.closeDrawer(),
                icon: const Icon(Icons.menu_open),
              ),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < _destinations.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  autofocus: i == _index,
                  selected: i == _index,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  selectedTileColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  leading: Icon(_destinations[i].$3),
                  title: Text(_destinations[i].$2),
                  minTileHeight: 56,
                  onTap: () => _navigate(i),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
