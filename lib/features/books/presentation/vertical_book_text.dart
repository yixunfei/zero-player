import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:fwfh_svg/fwfh_svg.dart';
import 'vertical_epub_flow.dart';

/// Upright CJK columns flowing right to left, with intact mixed-content pages.
class VerticalBookText extends StatefulWidget {
  const VerticalBookText({
    super.key,
    required this.text,
    this.html,
    required this.style,
    required this.onBoundary,
    this.initialPage = 0,
    this.onPageChanged,
  });
  final String text;
  final String? html;
  final TextStyle style;
  final ValueChanged<int> onBoundary;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  @override
  State<VerticalBookText> createState() => VerticalBookTextState();
}

class VerticalBookTextState extends State<VerticalBookText> {
  late final _pages = PageController(
    initialPage: widget.initialPage,
    keepPage: false,
  );
  late int _index = widget.initialPage;
  List<VerticalPage>? _layout;
  Size? _size;
  void turn(int direction) {
    final next = _index + direction;
    if (next < 0 || next >= (_layout?.length ?? 1)) {
      widget.onBoundary(direction);
      return;
    }
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant VerticalBookText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.html != widget.html) {
      _index = widget.initialPage;
      _layout = null;
      if (_pages.hasClients) _pages.jumpToPage(_index);
    } else if (oldWidget.style != widget.style) {
      _layout = null;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      if (_layout == null || _size != size) {
        _size = size;
        _layout = paginateVertical(
          verticalEpubItems(
            widget.html ??
                '<p>${htmlEscape.convert(widget.text).replaceAll('\n', '<br>')}</p>',
            widget.style,
          ),
          size,
        );
        final clamped = _index.clamp(0, _layout!.length - 1);
        if (clamped != _index) {
          _index = clamped;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_pages.hasClients) _pages.jumpToPage(_index);
            widget.onPageChanged?.call(_index);
          });
        }
      }
      return PageView.builder(
        controller: _pages,
        reverse: true,
        itemCount: _layout!.length,
        onPageChanged: (i) {
          _index = i;
          widget.onPageChanged?.call(i);
        },
        itemBuilder: (_, page) => _page(_layout![page]),
      );
    },
  );

  Widget _page(VerticalPage page) {
    if (page.html != null) {
      return SingleChildScrollView(
        child: HtmlWidget(
          page.html!,
          factoryBuilder: () => _VerticalFactory(),
          textStyle: widget.style,
          onTapUrl: (_) => true,
          customStylesBuilder: (e) => e.localName == 'pre'
              ? {
                  'white-space': 'pre',
                  'overflow': 'auto',
                  'font-family': 'monospace',
                }
              : null,
        ),
      );
    }
    return Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final col in page.columns)
          SizedBox(
            width: col.width,
            child: Column(
              children: [for (final item in col.items) _glyph(item)],
            ),
          ),
      ],
    );
  }

  Widget _glyph(VerticalItem item) {
    const punctuation = {
      '，': '︐',
      '。': '︒',
      '、': '︑',
      '：': '︓',
      '；': '︔',
      '（': '︵',
      '）': '︶',
      '「': '﹁',
      '」': '﹂',
      '『': '﹃',
      '』': '﹄',
    };
    return SizedBox(
      width: double.infinity,
      height: item.extent,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          SizedBox(
            width: (item.style.fontSize ?? 21) * 1.25,
            child: Center(
              child: Text(
                punctuation[item.text] ?? item.text,
                style: item.style.copyWith(height: 1),
              ),
            ),
          ),
          if (item.ruby.isNotEmpty)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: (item.style.fontSize ?? 21) * .45,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.ruby.characters.join('\n'),
                    textAlign: TextAlign.center,
                    style: item.style.copyWith(
                      fontSize: (item.style.fontSize ?? 21) * .45,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VerticalFactory extends WidgetFactory with SvgFactory {}
