import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../books/data/book_cover_cache.dart';

final class BookCoverCacheSetting extends StatefulWidget {
  const BookCoverCacheSetting({
    super.key,
    required this.services,
    required this.limitMiB,
  });

  final AppServices services;
  final int limitMiB;

  @override
  State<BookCoverCacheSetting> createState() => _BookCoverCacheSettingState();
}

final class _BookCoverCacheSettingState extends State<BookCoverCacheSetting> {
  late Future<BookCoverCacheUsage> _usage = widget.services.books.coverCache
      .usage();

  @override
  void initState() {
    super.initState();
    widget.services.books.coverCache.addListener(_refresh);
  }

  @override
  void didUpdateWidget(BookCoverCacheSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.services, widget.services)) {
      oldWidget.services.books.coverCache.removeListener(_refresh);
      widget.services.books.coverCache.addListener(_refresh);
    }
    if (oldWidget.limitMiB != widget.limitMiB ||
        !identical(oldWidget.services, widget.services)) {
      _refresh();
    }
  }

  @override
  void dispose() {
    widget.services.books.coverCache.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {
    _usage = widget.services.books.coverCache.usage();
  });

  Future<void> _clear() async {
    await perform(context, () async {
      await widget.services.books.coverCache.clear();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }, success: '书籍封面缓存已清理');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BookCoverCacheUsage>(
    future: _usage,
    builder: (context, snapshot) {
      final usage = snapshot.data;
      final label = snapshot.hasError
          ? '占用统计失败，可尝试清理'
          : usage == null
          ? '正在统计占用空间…'
          : '${usage.entries} 张 · ${(usage.bytes / 1048576).toStringAsFixed(1)} MiB / ${widget.limitMiB} MiB';
      return ListTile(
        title: const Text('清理书籍封面缓存'),
        subtitle: Text(label),
        trailing: const Icon(Icons.cleaning_services_outlined),
        onTap: usage?.entries == 0 || (usage == null && !snapshot.hasError)
            ? null
            : _clear,
      );
    },
  );
}
