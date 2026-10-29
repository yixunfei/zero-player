import 'package:flutter/material.dart';

/// Less frequent destinations remain reachable in the full navigation menu.
final class MobileBottomNavigation extends StatelessWidget {
  const MobileBottomNavigation({
    super.key,
    required this.location,
    required this.onNavigate,
    required this.onMore,
  });
  final String location;
  final ValueChanged<String> onNavigate;
  final VoidCallback onMore;
  static const _routes = ['/', '/search', '/live', '/history'];

  @override
  Widget build(BuildContext context) {
    final selected = _routes.indexOf(location);
    return NavigationBar(
      key: const ValueKey('mobile-bottom-navigation'),
      height: 64,
      selectedIndex: selected < 0 ? 4 : selected,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) =>
          index == 4 ? onMore() : onNavigate(_routes[index]),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.explore_outlined), label: '发现'),
        NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
        NavigationDestination(icon: Icon(Icons.live_tv), label: '直播'),
        NavigationDestination(icon: Icon(Icons.history), label: '记录'),
        NavigationDestination(icon: Icon(Icons.menu), label: '更多'),
      ],
    );
  }
}
