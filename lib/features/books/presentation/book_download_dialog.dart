import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class BookDownloadPlan {
  const BookDownloadPlan(
    this.first,
    this.last,
    this.fallback, {
    this.chapterIds,
  });
  final int first, last;
  final bool fallback;
  final List<String>? chapterIds;

  static BookDownloadPlan? fromJson(Object? value) {
    if (value case {
      'first': final int first,
      'last': final int last,
      'fallback': final bool fallback,
    }) {
      if (first >= 1 && last >= first) {
        final ids = (value as Map)['chapterIds'];
        return BookDownloadPlan(
          first,
          last,
          fallback,
          chapterIds: ids is List
              ? ids.whereType<String>().take(4000).toList()
              : null,
        );
      }
    }
    return null;
  }

  Map<String, Object> toJson() => {
    'first': first,
    'last': last,
    'fallback': fallback,
    'chapterIds': ?chapterIds,
  };
}

Future<BookDownloadPlan?> showBookDownloadDialog(
  BuildContext context,
  int total,
) {
  var first = 1, last = total;
  var all = true, fallback = false;
  return showDialog<BookDownloadPlan>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('离线下载'),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('全本')),
                  ButtonSegment(value: false, label: Text('指定区间')),
                ],
                selected: {all},
                onSelectionChanged: (values) =>
                    update(() => all = values.single),
              ),
              const SizedBox(height: 12),
              if (!all)
                Row(
                  children: [
                    Expanded(
                      child: _chapterNumber(
                        '起始章节',
                        first,
                        (value) => update(() => first = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _chapterNumber(
                        '结束章节',
                        last,
                        (value) => update(() => last = value),
                      ),
                    ),
                  ],
                ),
              Text('共 $total 章，自动跳过已下载章节'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('失败时尝试其他书源'),
                subtitle: const Text('只下载同名同作者且章节唯一对应的版本'),
                value: fallback,
                onChanged: (value) => update(() => fallback = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: all || (first >= 1 && last >= first && last <= total)
                ? () => Navigator.pop(
                    context,
                    BookDownloadPlan(
                      all ? 1 : first,
                      all ? total : last,
                      fallback,
                    ),
                  )
                : null,
            child: const Text('开始下载'),
          ),
        ],
      ),
    ),
  );
}

Widget _chapterNumber(String label, int initial, ValueChanged<int> onChange) =>
    TextFormField(
      initialValue: '$initial',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => onChange(int.tryParse(value) ?? 0),
    );
