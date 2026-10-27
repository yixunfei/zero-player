import 'package:flutter/material.dart';
import 'poster_image.dart';
import 'synopsis_text.dart';

/// The same information drawer works with pointer, remote focus and touch.
final class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.poster,
    required this.subtitle,
    required this.onTap,
    this.description = '',
    this.loadDescription,
  });
  final String title, poster, subtitle, description;
  final VoidCallback onTap;
  final Future<String> Function()? loadDescription;
  @override
  State<PosterCard> createState() => _PosterCardState();
}

final class _PosterCardState extends State<PosterCard> {
  bool _hover = false, _focus = false, _pinned = false;
  bool get _expanded =>
      _hover ||
      (_focus &&
          FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional) ||
      _pinned;
  Duration get _duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: _duration,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _expanded ? scheme.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            if (_expanded)
              BoxShadow(
                color: scheme.primary.withValues(alpha: .12),
                blurRadius: 16,
              ),
          ],
        ),
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (value) => setState(() => _focus = value),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _cover()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover() => LayoutBuilder(
    builder: (context, constraints) => ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSlide(
            offset: _expanded ? const Offset(0, -.08) : Offset.zero,
            duration: _duration,
            curve: Curves.easeOutCubic,
            child: PosterImage(url: widget.poster),
          ),
          IgnorePointer(
            child: AnimatedSlide(
              offset: _expanded ? Offset.zero : const Offset(0, 1),
              duration: _duration,
              curve: Curves.easeOutCubic,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .8,
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xcc101219), Color(0xfa101219)],
                    ),
                  ),
                  child: _information(),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filledTonal(
              tooltip: _pinned ? '收起节目简介' : '展开节目简介',
              isSelected: _pinned,
              onPressed: () => setState(() => _pinned = !_pinned),
              icon: const Icon(Icons.info_outline, size: 20),
              selectedIcon: const Icon(Icons.close, size: 20),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _information() => ExcludeSemantics(
    excluding: !_expanded,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Flexible(
          child:
              widget.description.trim().isEmpty &&
                  widget.loadDescription != null
              ? (_expanded
                    ? SynopsisText(
                        key: ValueKey(widget.poster),
                        load: widget.loadDescription!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      )
                    : const SizedBox.shrink())
              : Text(
                  widget.description.trim().isEmpty
                      ? '暂无剧情简介，打开详情查看片源与剧集。'
                      : widget.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
        ),
      ],
    ),
  );
}
