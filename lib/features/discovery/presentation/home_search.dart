import 'package:flutter/material.dart';

/// A compact search entry that shares the channel toolbar's row.
final class HomeSearch extends StatelessWidget {
  const HomeSearch({super.key, required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('home-search'),
            onPressed: onSearch,
            icon: const Icon(Icons.search, size: 22),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('搜索影片', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              backgroundColor: colors.primaryContainer.withValues(alpha: .35),
              foregroundColor: colors.primary,
              side: BorderSide(color: colors.primary, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ),
    );
  }
}
