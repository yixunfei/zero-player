import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/poster_repository.dart';
import 'app_services.dart';

/// Recycled cards release their network leases immediately.
final class PosterImage extends ConsumerStatefulWidget {
  const PosterImage({
    super.key,
    required this.url,
    this.width = 440,
    this.fit = BoxFit.cover,
  });
  final String url;
  final int width;
  final BoxFit fit;
  @override
  ConsumerState<PosterImage> createState() => _PosterImageState();
}

final class _PosterImageState extends ConsumerState<PosterImage> {
  PosterLease? _lease;
  late final PosterRepository _repository;
  @override
  void initState() {
    super.initState();
    _repository = ref.read(servicesProvider).posters;
    _load();
  }

  void _load() {
    _lease?.release();
    _lease = widget.url.trim().isEmpty ? null : _repository.acquire(widget.url);
  }

  @override
  void didUpdateWidget(PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  @override
  void dispose() {
    _lease?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    key: ValueKey(widget.url),
    future: _lease?.bytes,
    builder: (_, snapshot) {
      if (snapshot.hasData) {
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          cacheWidth: widget.width.clamp(120, 960),
          filterQuality: FilterQuality.medium,
          frameBuilder: (_, child, frame, sync) =>
              frame != null || sync ? child : _placeholder(),
          errorBuilder: (_, _, _) => _placeholder(failed: true),
        );
      }
      return _placeholder(failed: snapshot.hasError);
    },
  );

  Widget _placeholder({bool failed = false}) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_outlined,
            size: 36,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          if (failed)
            TextButton(
              onPressed: () => setState(() {
                _repository.retry(widget.url);
                _load();
              }),
              child: const Text(
                '封面暂不可用 · 重试',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    ),
  );
}
