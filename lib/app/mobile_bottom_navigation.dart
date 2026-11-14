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
  static const _routes = ['/', '/live', '/music', '/reading'];

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
        NavigationDestination(icon: Icon(Icons.movie_outlined), label: '影院'),
        NavigationDestination(icon: Icon(Icons.live_tv), label: '直播'),
        NavigationDestination(
          icon: Icon(Icons.library_music_outlined),
          label: '音乐',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_stories_outlined),
          label: '网络小说',
        ),
        NavigationDestination(icon: Icon(Icons.menu), label: '更多'),
      ],
    );
  }
}
