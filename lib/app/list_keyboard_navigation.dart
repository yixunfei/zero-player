import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lives inside a route, below the Navigator's own primary-scroll scope.
final class PageListNavigation extends StatefulWidget {
  const PageListNavigation({super.key, required this.child});
  final Widget child;
  @override
  State<PageListNavigation> createState() => _PageListNavigationState();
}

final class _PageListNavigationState extends State<PageListNavigation> {
  final _controller = ScrollController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PrimaryScrollController(
    controller: _controller,
    automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
    child: ListKeyboardNavigation(controller: _controller, child: widget.child),
  );
}

/// Keyboard scrolling for the active page, without stealing text editing keys.
final class ListKeyboardNavigation extends StatefulWidget {
  const ListKeyboardNavigation({
    super.key,
    required this.controller,
    required this.child,
  });
  final ScrollController controller;
  final Widget child;
  @override
  State<ListKeyboardNavigation> createState() => _ListKeyboardNavigationState();
}

final class _ListKeyboardNavigationState extends State<ListKeyboardNavigation> {
  int _navigation = 0;
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    _navigation++;
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  bool _key(KeyEvent event) {
    if (!mounted ||
        event is KeyUpEvent ||
        !widget.controller.hasClients ||
        widget.controller.positions.length != 1 ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null ||
            ModalRoute.of(focused) is PopupRoute)) {
      return false;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }
    final position = widget.controller.position;
    if (position.axis != Axis.vertical) return false;
    final key = event.logicalKey;
    final target = key == LogicalKeyboardKey.home
        ? position.minScrollExtent
        : key == LogicalKeyboardKey.end
        ? position.maxScrollExtent
        : key == LogicalKeyboardKey.pageUp
        ? position.pixels - position.viewportDimension * .85
        : key == LogicalKeyboardKey.pageDown
        ? position.pixels + position.viewportDimension * .85
        : null;
    if (target == null) return false;
    final offset = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final generation = ++_navigation;
    unawaited(_move(offset, key, generation));
    return true;
  }

  Future<void> _move(
    double offset,
    LogicalKeyboardKey key,
    int generation,
  ) async {
    final immediate = MediaQuery.disableAnimationsOf(context);
    if (immediate) {
      widget.controller.jumpTo(offset);
    } else {
      await widget.controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    // Lazy rows and the collapsing header can revise the measured extent
    // during scrolling. Correct End against the newly laid-out boundary.
    if (key != LogicalKeyboardKey.end) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _navigation ||
          widget.controller.positions.length != 1) {
        return;
      }
      final position = widget.controller.position;
      if ((position.maxScrollExtent - position.pixels).abs() < 1) return;
      widget.controller.jumpTo(position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
