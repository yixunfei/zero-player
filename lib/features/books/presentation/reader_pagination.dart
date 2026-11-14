import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'reader_curl.dart';
import 'reader_style.dart';

/// Positions from older builds contain only a fraction of the chapter.
typedef ReaderProgress = ({double fraction, int? offset, int page, int pages});

ReaderProgress readerProgress(double fraction, {int? offset}) =>
    (fraction: fraction, offset: offset, page: 0, pages: 0);

List<String> paginateReadingText(
  String text,
  TextStyle style,
  Size size,
  TextScaler scaler,
  TextDirection direction,
) {
  final layout = _ReaderLayout(text, style, size, scaler, direction);
  return [
    for (final page in layout.slices) text.substring(page.start, page.end),
  ];
}

final class _ReadingSlice {
  const _ReadingSlice(
    this.start,
    this.end,
    this.visibleEnd,
    this.top,
    this.height,
  );
  final int start, end, visibleEnd;
  final double top, height;
}

final class _ReaderLayout {
  _ReaderLayout(
    this.text,
    this.style,
    this.size,
    this.scaler,
    this.direction, {
    this.headingEnd = 0,
  }) {
    final fontSize = scaler.scale(style.fontSize ?? 21).clamp(1, 160);
    final capacity =
        (size.width /
        (fontSize * .52) *
        size.height /
        (fontSize * (style.height ?? 1.5)));
    final window = (capacity * 2.2).ceil().clamp(512, 6500);
    final painter = _painter();
    var start = 0;
    var top = 0.0;
    try {
      while (start < text.length) {
        var end = math.min(start + window, text.length);
        if (end < text.length && _lowSurrogate(text.codeUnitAt(end))) end--;
        painter.text = span(start, end);
        painter.layout(maxWidth: size.width);
        if (painter.height > size.height) {
          end = _lastVisibleOffset(painter, start, end);
        }
        if (end <= start) {
          end =
              start +
              text
                  .substring(start, math.min(start + window, text.length))
                  .characters
                  .first
                  .length;
        }
        final visibleEnd = text.codeUnitAt(end - 1) == 10 ? end - 1 : end;
        painter.text = span(start, visibleEnd);
        painter.layout(maxWidth: size.width);
        slices.add(_ReadingSlice(start, end, visibleEnd, top, painter.height));
        top += painter.height;
        start = end;
      }
    } finally {
      painter.dispose();
    }
    if (slices.isEmpty) slices.add(const _ReadingSlice(0, 0, 0, 0, 0));
    totalHeight = top;
  }

  final String text;
  final TextStyle style;
  final Size size;
  final TextScaler scaler;
  final TextDirection direction;
  final int headingEnd;
  final slices = <_ReadingSlice>[];
  late final double totalHeight;
  double get maxScroll => math.max(0, totalHeight - size.height);

  static bool _lowSurrogate(int value) => value >= 0xdc00 && value <= 0xdfff;

  TextPainter _painter() =>
      TextPainter(textDirection: direction, textScaler: scaler);

  int _lastVisibleOffset(TextPainter painter, int start, int end) {
    final metrics = painter.computeLineMetrics();
    final last =
        metrics
            .where((line) => line.baseline + line.descent <= size.height)
            .lastOrNull ??
        metrics.firstOrNull;
    if (last == null) return end;
    final cursor = painter.getPositionForOffset(
      Offset(last.left + last.width / 2, last.baseline - last.ascent / 2),
    );
    var boundary = start + painter.getLineBoundary(cursor).end;
    if (boundary < end && text.codeUnitAt(boundary) == 10) boundary++;
    return boundary;
  }

  int indexForOffset(int offset) =>
      _indexWhere((slice) => slice.start <= offset);
  int indexForPixels(double pixels) =>
      _indexWhere((slice) => slice.top <= pixels);

  int _indexWhere(bool Function(_ReadingSlice) before) {
    var first = 0, last = slices.length;
    while (first + 1 < last) {
      final center = (first + last) ~/ 2;
      if (before(slices[center])) {
        first = center;
      } else {
        last = center;
      }
    }
    return first;
  }

  double pixelsForOffset(int offset, {bool center = false}) {
    final page = slices[indexForOffset(offset)];
    final painter = _painter()
      ..text = span(page.start, page.visibleEnd)
      ..layout(maxWidth: size.width);
    try {
      final caret = painter.getOffsetForCaret(
        TextPosition(
          offset: (offset - page.start).clamp(0, page.visibleEnd - page.start),
        ),
        Rect.zero,
      );
      return (page.top + caret.dy - (center ? size.height * .32 : 0)).clamp(
        0.0,
        maxScroll,
      );
    } finally {
      painter.dispose();
    }
  }

  int offsetForPixels(double pixels) {
    final page = slices[indexForPixels(pixels)];
    if (page.height <= 0) return page.start;
    final fraction = ((pixels - page.top) / page.height).clamp(0.0, 1.0);
    return page.start + (fraction * (page.visibleEnd - page.start)).round();
  }

  TextSpan span(
    int start,
    int end, {
    TextRange? highlight,
    Color? highlightColor,
  }) {
    final boundaries = <int>{
      start,
      end,
      if (headingEnd > start && headingEnd < end) headingEnd,
      if (highlight != null && highlight.start > start && highlight.start < end)
        highlight.start,
      if (highlight != null && highlight.end > start && highlight.end < end)
        highlight.end,
    }.toList()..sort();
    return TextSpan(
      style: style,
      children: [
        for (var i = 1; i < boundaries.length; i++)
          TextSpan(
            text: text.substring(boundaries[i - 1], boundaries[i]),
            style: TextStyle(
              fontSize: boundaries[i - 1] < headingEnd
                  ? (style.fontSize ?? 21) + 5
                  : null,
              fontWeight: boundaries[i - 1] < headingEnd
                  ? FontWeight.w700
                  : null,
              backgroundColor:
                  highlight != null &&
                      boundaries[i - 1] >= highlight.start &&
                      boundaries[i] <= highlight.end
                  ? highlightColor
                  : null,
            ),
          ),
      ],
    );
  }
}

class ReaderViewport extends StatefulWidget {
  const ReaderViewport({
    super.key,
    required this.text,
    required this.titleLength,
    required this.style,
    required this.palette,
    required this.mode,
    required this.animate,
    required this.texture,
    required this.margin,
    required this.initial,
    required this.onProgress,
    required this.canCross,
    required this.onBoundary,
    required this.onSelection,
    required this.onAnnotate,
    this.highlight,
  });

  final String text;
  final int titleLength;
  final TextStyle style;
  final ReaderPalette palette;
  final ReaderTurnMode mode;
  final bool animate;
  final bool texture;
  final double margin;
  final ReaderProgress initial;
  final TextRange? highlight;
  final ValueChanged<ReaderProgress> onProgress;
  final bool Function(int direction) canCross;
  final ValueChanged<int> onBoundary;
  final ValueChanged<String> onSelection;
  final VoidCallback onAnnotate;

  @override
  State<ReaderViewport> createState() => ReaderViewportState();
}

class ReaderViewportState extends State<ReaderViewport> {
  final _curl = GlobalKey<ReaderCurlState>();
  final _selectionArea = GlobalKey<SelectionAreaState>();
  PageController? _pager;
  ScrollController? _scroller;
  _ReaderLayout? _layout;
  Object? _layoutKey;
  late ReaderProgress _progress = widget.initial;
  int _index = 0;
  double _overscroll = 0;
  bool _startEdge = false, _endEdge = false;
  bool get _scrolling => widget.mode == ReaderTurnMode.scroll;
  bool get _animate =>
      widget.animate && !MediaQuery.disableAnimationsOf(context);

  void jump(double fraction) {
    final layout = _layout;
    if (layout == null) return;
    if (_scrolling) {
      _jumpScroll(layout.maxScroll * fraction);
    } else {
      _jumpPage(((layout.slices.length - 1) * fraction).round());
    }
  }

  void jumpToOffset(int offset) {
    final layout = _layout;
    if (layout == null) return;
    if (_scrolling) {
      _jumpScroll(layout.pixelsForOffset(offset, center: true));
    } else {
      _jumpPage(layout.indexForOffset(offset));
    }
  }

  void _jumpScroll(double pixels) {
    final controller = _scroller;
    if (controller == null || !controller.hasClients) return;
    controller.jumpTo(pixels.clamp(0.0, controller.position.maxScrollExtent));
  }

  void _jumpPage(int index) {
    if (_pager?.hasClients == true) {
      _pager!.jumpToPage(index);
    } else if (widget.mode == ReaderTurnMode.curl) {
      _pageChanged(index);
    }
  }

  bool autoScroll(double pixels) {
    final controller = _scroller;
    if (controller == null || !controller.hasClients) return true;
    final position = controller.position;
    if (!position.hasContentDimensions) return true;
    if (position.pixels >= position.maxScrollExtent - .01) return false;
    controller.jumpTo(
      (position.pixels + pixels).clamp(0.0, position.maxScrollExtent),
    );
    return true;
  }

  void turn(int direction) {
    final layout = _layout;
    if (layout == null) return;
    if (_scrolling) {
      _scrollPage(direction);
      return;
    }
    if (widget.mode == ReaderTurnMode.curl) {
      _curl.currentState?.turn(direction);
      return;
    }
    final next = _index + direction;
    if (next < 0 || next >= layout.slices.length) {
      widget.onBoundary(direction);
      return;
    }
    final pager = _pager;
    if (pager == null || !pager.hasClients) return;
    if (_animate) {
      pager.animateToPage(
        next,
        duration: const Duration(milliseconds: 225),
        curve: Curves.easeOutCubic,
      );
    } else {
      pager.jumpToPage(next);
    }
  }

  void _scrollPage(int direction) {
    final controller = _scroller;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final atEdge = direction > 0
        ? position.pixels >= position.maxScrollExtent - 1
        : position.pixels <= position.minScrollExtent + 1;
    if (atEdge) {
      widget.onBoundary(direction);
      return;
    }
    final target =
        (position.pixels + direction * position.viewportDimension * .88).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if (_animate) {
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _pager?.dispose();
    _scroller?.dispose();
    super.dispose();
  }

  void _pageChanged(int index) {
    final layout = _layout!;
    if (index == _index) return;
    setState(() => _index = index);
    _selectionArea.currentState?.selectableRegion.clearSelection();
    widget.onSelection('');
    _publish(_pageProgress(layout));
  }

  ReaderProgress _pageProgress(_ReaderLayout layout) => (
    fraction: layout.slices.length <= 1
        ? 0
        : _index / (layout.slices.length - 1),
    offset: layout.slices[_index].start,
    page: _index + 1,
    pages: layout.slices.length,
  );

  ReaderProgress _scrollProgress(
    _ReaderLayout layout,
    double pixels,
    double max,
  ) => (
    fraction: max <= 0 ? 0 : (pixels / max).clamp(0.0, 1.0),
    offset: layout.offsetForPixels(pixels),
    page: layout.indexForPixels(pixels) + 1,
    pages: layout.slices.length,
  );

  void _publish(ReaderProgress progress) {
    if (progress == _progress) return;
    _progress = progress;
    widget.onProgress(progress);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _startEdge = metrics.pixels <= metrics.minScrollExtent + 1;
      _endEdge = metrics.pixels >= metrics.maxScrollExtent - 1;
      _overscroll = 0;
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      if ((notification.overscroll < 0 && _startEdge) ||
          (notification.overscroll > 0 && _endEdge)) {
        _overscroll += notification.overscroll;
      }
    } else if (notification is ScrollEndNotification) {
      final distance = _overscroll;
      _overscroll = 0;
      _startEdge = _endEdge = false;
      if (distance.abs() >= 42) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onBoundary(distance > 0 ? 1 : -1);
        });
      }
    }
    final layout = _layout;
    if (_scrolling &&
        layout != null &&
        notification is ScrollUpdateNotification) {
      _publish(
        _scrollProgress(layout, metrics.pixels, metrics.maxScrollExtent),
      );
    }
    return false;
  }

  void _relayout(Size size, TextScaler scaler, TextDirection direction) {
    final key = (
      widget.text,
      widget.titleLength,
      widget.style,
      size,
      scaler,
      direction,
    );
    if (_layoutKey != key) {
      _layout = _ReaderLayout(
        widget.text,
        widget.style,
        size,
        scaler,
        direction,
        headingEnd: widget.titleLength,
      );
      _layoutKey = key;
    }
    final layout = _layout!;
    final offset = _progress.offset;
    _index = offset == null
        ? ((_progress.fraction * (layout.slices.length - 1)).round()).clamp(
            0,
            layout.slices.length - 1,
          )
        : layout.indexForOffset(offset);
    final previousPager = _pager;
    final previousScroller = _scroller;
    final initialScroll = _scrolling
        ? offset == null
              ? _progress.fraction * layout.maxScroll
              : layout.pixelsForOffset(offset)
        : 0.0;
    _pager = widget.mode == ReaderTurnMode.curl || _scrolling
        ? null
        : PageController(initialPage: _index, keepPage: false);
    _scroller = _scrolling
        ? ScrollController(
            initialScrollOffset: initialScroll,
            keepScrollOffset: false,
          )
        : null;
    _overscroll = 0;
    _startEdge = _endEdge = false;
    final mode = widget.mode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousPager?.dispose();
      previousScroller?.dispose();
      if (!mounted || _layout != layout || widget.mode != mode) return;
      final progress = _scrolling
          ? _scrollProgress(layout, initialScroll, layout.maxScroll)
          : _pageProgress(layout);
      _publish((
        fraction: progress.fraction,
        offset: offset ?? progress.offset,
        page: progress.page,
        pages: progress.pages,
      ));
    });
  }

  Widget _text(int index) {
    final layout = _layout!;
    final page = layout.slices[index];
    return Text.rich(
      layout.span(
        page.start,
        page.visibleEnd,
        highlight: widget.highlight,
        highlightColor: widget.palette.accent.withValues(alpha: .28),
      ),
    );
  }

  Widget _pageText(int index, EdgeInsets padding) => Padding(
    padding: padding,
    child: Align(alignment: Alignment.topLeft, child: _text(index)),
  );

  Widget _selectable(Widget child) => SelectionArea(
    key: _selectionArea,
    onSelectionChanged: (selection) =>
        widget.onSelection(selection?.plainText ?? ''),
    contextMenuBuilder: (context, region) =>
        AdaptiveTextSelectionToolbar.buttonItems(
          anchors: region.contextMenuAnchors,
          buttonItems: [
            ...region.contextMenuButtonItems,
            ContextMenuButtonItem(
              label: '摘录或写笔记',
              onPressed: () {
                widget.onAnnotate();
                ContextMenuController.removeAny();
              },
            ),
          ],
        ),
    child: child,
  );

  ReaderTurnMode? _laidOutMode;
  static const _physics = ClampingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final side = math.max(widget.margin, (constraints.maxWidth - 840) / 2);
      final pagePadding = EdgeInsets.fromLTRB(side, 8, side, 30);
      final size = Size(
        math.max(1, constraints.maxWidth - pagePadding.horizontal),
        math.max(1, constraints.maxHeight - pagePadding.vertical),
      );
      final key = (
        widget.text,
        widget.titleLength,
        widget.style,
        size,
        scaler,
        direction,
      );
      if (_layoutKey != key || _laidOutMode != widget.mode) {
        _relayout(size, scaler, direction);
        _laidOutMode = widget.mode;
      }
      final layout = _layout!;
      // The scroll or curl recognizer receives a horizontal drag before the
      // selection area. Long presses and mouse selection still reach the text.
      return ClipRect(
        child: _selectable(switch (widget.mode) {
          ReaderTurnMode.curl => ReaderCurl(
            key: _curl,
            paper: widget.palette.paper,
            background: ReaderPaperSurface(
              palette: widget.palette,
              texture: widget.texture,
            ),
            animate: _animate,
            page: _index,
            canTurn: (delta) {
              final target = _index + delta;
              return target >= 0 && target < layout.slices.length ||
                  widget.canCross(delta);
            },
            onTurn: (delta) {
              final target = _index + delta;
              if (target >= 0 && target < layout.slices.length) {
                _pageChanged(target);
              } else {
                widget.onBoundary(delta);
              }
            },
            pageBuilder: (index, selectable) {
              if (index < 0 || index >= layout.slices.length) {
                return const SizedBox.expand();
              }
              final page = _pageText(index, pagePadding);
              return selectable
                  ? page
                  : SelectionContainer.disabled(child: page);
            },
          ),
          ReaderTurnMode.scroll => Padding(
            padding: pagePadding,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: Scrollbar(
                controller: _scroller,
                child: ListView.builder(
                  key: ValueKey(_scroller),
                  controller: _scroller,
                  physics: _physics,
                  padding: EdgeInsets.zero,
                  itemCount: layout.slices.length,
                  itemExtentBuilder: (index, _) => index < layout.slices.length
                      ? layout.slices[index].height
                      : null,
                  itemBuilder: (_, index) =>
                      Align(alignment: Alignment.topLeft, child: _text(index)),
                ),
              ),
            ),
          ),
          _ => NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: PageView.builder(
              key: ValueKey(_pager),
              controller: _pager,
              physics: _physics,
              scrollDirection: widget.mode.horizontal
                  ? Axis.horizontal
                  : Axis.vertical,
              itemCount: layout.slices.length,
              onPageChanged: _pageChanged,
              itemBuilder: (_, index) => _pageText(index, pagePadding),
            ),
          ),
        }),
      );
    },
  );
}

/// Pointer taps coexist with text selection and the viewport's drag gestures.
class ReaderTapZones extends StatefulWidget {
  const ReaderTapZones({
    super.key,
    required this.horizontal,
    required this.selectionActive,
    required this.onTurn,
    required this.onMenu,
    required this.child,
  });
  final bool horizontal;
  final bool Function() selectionActive;
  final ValueChanged<int> onTurn;
  final VoidCallback onMenu;
  final Widget child;

  @override
  State<ReaderTapZones> createState() => _ReaderTapZonesState();
}

class _ReaderTapZonesState extends State<ReaderTapZones> {
  PointerDownEvent? _start;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_start != null || widget.selectionActive()) {
          _start = null;
        } else if (event.buttons == kPrimaryButton) {
          _start = event;
        }
      },
      onPointerMove: (event) {
        final start = _start;
        if (start != null &&
            start.pointer == event.pointer &&
            (event.position - start.position).distance > 12) {
          _start = null;
        }
      },
      onPointerCancel: (_) => _start = null,
      onPointerUp: (event) {
        final start = _start;
        _start = null;
        if (start == null ||
            start.pointer != event.pointer ||
            event.timeStamp - start.timeStamp >
                const Duration(milliseconds: 340) ||
            widget.selectionActive()) {
          return;
        }
        final fraction = widget.horizontal
            ? event.localPosition.dx / constraints.maxWidth
            : event.localPosition.dy / constraints.maxHeight;
        if (fraction < .28) {
          widget.onTurn(-1);
        } else if (fraction > .72) {
          widget.onTurn(1);
        } else {
          widget.onMenu();
        }
      },
      child: widget.child,
    ),
  );
}
