import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/network/cancellation_token.dart';
import '../data/book_mixed_content.dart';

typedef ChapterImageLoader =
    Future<List<int>> Function(Uri address, CancellationToken token);

/// Lazily loads an image chapter through the book source's media policy.
class BookImageChapter extends StatefulWidget {
  const BookImageChapter({
    super.key,
    required this.loadImage,
    required this.images,
    this.segments,
    required this.onNext,
    this.onPrevious,
    this.initialFraction = 0,
    this.onProgress,
  });

  final ChapterImageLoader loadImage;
  final List<Uri> images;
  final List<BookChapterSegment>? segments;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final double initialFraction;
  final ValueChanged<double>? onProgress;

  @override
  BookImageChapterState createState() => BookImageChapterState();
}

class BookImageChapterState extends State<BookImageChapter> {
  final ScrollController _scroll = ScrollController();
  bool _restoring = true;
  bool _userMoved = false;
  bool _restoreScheduled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_reportProgress);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  void _restore() {
    _restoreScheduled = false;
    if (!mounted || !_scroll.hasClients) return;
    if (_userMoved) return;
    final max = _scroll.position.maxScrollExtent;
    if (max > 0 && widget.initialFraction > 0) {
      _restoring = true;
      _scroll.jumpTo(max * widget.initialFraction.clamp(0.0, 1.0));
    }
    _restoring = false;
  }

  void _scheduleRestore() {
    if (_userMoved || _restoreScheduled || widget.initialFraction <= 0) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  void _reportProgress() {
    if (_restoring || !_scroll.hasClients) return;
    _userMoved = true;
    final max = _scroll.position.maxScrollExtent;
    widget.onProgress?.call(max <= 0 ? 0 : (_scroll.offset / max).clamp(0, 1));
  }

  void turn(int direction) {
    if (!_scroll.hasClients || direction == 0) return;
    final position = _scroll.position;
    final target =
        (position.pixels + direction * position.viewportDimension * .85)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    if ((target - position.pixels).abs() < 1) {
      if (direction > 0) {
        widget.onNext?.call();
      } else {
        widget.onPrevious?.call();
      }
      return;
    }
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts =
        widget.segments ??
        [for (final image in widget.images) BookImageSegment(image)];
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleRestore();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemCount: parts.length + 1,
        itemBuilder: (context, index) {
          if (index == parts.length) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: FilledButton.icon(
                  onPressed: widget.onNext,
                  icon: const Icon(Icons.navigate_next),
                  label: Text(widget.onNext == null ? '本章已结束' : '下一章'),
                ),
              ),
            );
          }
          final part = parts[index];
          if (part is BookTextSegment) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: SelectableText(
                part.text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          final address = (part as BookImageSegment).address;
          return _ChapterImage(
            key: ValueKey('$index:$address'),
            loadImage: widget.loadImage,
            address: address,
            index: parts.take(index + 1).whereType<BookImageSegment>().length,
          );
        },
      ),
    );
  }
}

class _ChapterImage extends StatefulWidget {
  const _ChapterImage({
    super.key,
    required this.loadImage,
    required this.address,
    required this.index,
  });

  final ChapterImageLoader loadImage;
  final Uri address;
  final int index;

  @override
  State<_ChapterImage> createState() => _ChapterImageState();
}

class _ChapterImageState extends State<_ChapterImage> {
  final _token = CancellationToken();
  late Future<({Uint8List bytes, double aspect})> _image = _load();

  Future<({Uint8List bytes, double aspect})> _load() async {
    final bytes = Uint8List.fromList(
      await widget.loadImage(widget.address, _token),
    );
    _token.check();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final width = descriptor.width;
        final height = descriptor.height;
        if (width <= 0 || height <= 0 || width * height > 24000000) {
          throw const FormatException('章节图片像素超过限制');
        }
        _token.check();
        return (bytes: bytes, aspect: height / width);
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({Uint8List bytes, double aspect})>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: TextButton.icon(
                onPressed: () => setState(() => _image = _load()),
                icon: const Icon(Icons.refresh),
                label: Text('第 ${widget.index} 张图片加载失败，重试'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return SizedBox(
              height: MediaQuery.sizeOf(context).height,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          final content = snapshot.data!;
          final bytes = content.bytes;
          return Semantics(
            label: '第 ${widget.index} 张章节图片',
            child: InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog.fullscreen(
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        child: Center(child: Image.memory(bytes)),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: SafeArea(
                          child: IconButton(
                            tooltip: '关闭图片',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => Image.memory(
                  bytes,
                  width: constraints.maxWidth,
                  height: constraints.maxWidth * content.aspect,
                  fit: BoxFit.fitWidth,
                  cacheWidth:
                      (constraints.maxWidth *
                              MediaQuery.devicePixelRatioOf(context))
                          .ceil()
                          .clamp(1, 1600),
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('第 ${widget.index} 张图片格式无法解码'),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
