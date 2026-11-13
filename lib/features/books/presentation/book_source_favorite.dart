import 'package:flutter/material.dart';

import '../../supervision/presentation/sensitive_action.dart';
import '../data/book_store.dart';
import '../data/books_repository.dart';

class BookSourceFavorite extends StatefulWidget {
  const BookSourceFavorite({
    super.key,
    required this.repository,
    required this.entry,
    required this.onChanged,
  });
  final BooksRepository repository;
  final BookSourceEntry entry;
  final ValueChanged<bool> onChanged;

  @override
  State<BookSourceFavorite> createState() => _BookSourceFavoriteState();
}

class _BookSourceFavoriteState extends State<BookSourceFavorite> {
  bool _saving = false;

  Future<void> _toggle() async {
    final favorite = !widget.entry.favorite;
    final source = widget.entry.source;
    setState(() => _saving = true);
    try {
      final changed = await runSensitive(
        context,
        widget.repository.policy.supervision,
        SensitiveOperation.channels,
        () => widget.repository.saveSource(source, {'favorite': favorite}),
      );
      if (mounted && changed) widget.onChanged(favorite);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法更新渠道收藏')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: widget.entry.favorite ? '取消收藏渠道' : '收藏渠道',
    isSelected: widget.entry.favorite,
    icon: const Icon(Icons.star_border),
    selectedIcon: const Icon(Icons.star),
    onPressed: _saving ? null : _toggle,
  );
}
