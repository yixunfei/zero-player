import 'package:flutter/material.dart';
import '../application/search_options.dart';

Future<SearchOptions?> showAdvancedSearch(
  BuildContext context,
  SearchOptions initial,
) => showDialog<SearchOptions>(
  context: context,
  builder: (_) => _AdvancedSearch(initial),
);

class _AdvancedSearch extends StatefulWidget {
  const _AdvancedSearch(this.initial);
  final SearchOptions initial;
  @override
  State<_AdvancedSearch> createState() => _AdvancedSearchState();
}

class _AdvancedSearchState extends State<_AdvancedSearch> {
  late SearchMatch match = widget.initial.match;
  late SearchSort sort = widget.initial.sort;
  late int pages = widget.initial.maxPages;
  late final year = TextEditingController(text: widget.initial.year);
  late final area = TextEditingController(text: widget.initial.area);
  late final category = TextEditingController(text: widget.initial.category);
  late final exclude = TextEditingController(text: widget.initial.excludeWords);
  @override
  void dispose() {
    for (final field in [year, area, category, exclude]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('高级搜索'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('按来源返回的资料筛选；资料缺失的结果不会匹配已填写条件。每源仍受 10 秒查询预算限制。'),
            DropdownButtonFormField<SearchMatch>(
              initialValue: match,
              decoration: const InputDecoration(labelText: '匹配策略'),
              items: [
                for (final value in SearchMatch.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(['来源综合匹配', '片名包含关键词', '片名精确匹配'][value.index]),
                  ),
              ],
              onChanged: (value) => setState(() => match = value!),
            ),
            DropdownButtonFormField<SearchSort>(
              initialValue: sort,
              decoration: const InputDecoration(labelText: '排序'),
              items: [
                for (final value in SearchSort.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(['渠道优先', '相关度优先', '年份从新到旧'][value.index]),
                  ),
              ],
              onChanged: (value) => setState(() => sort = value!),
            ),
            for (final field in [
              (year, '年份（精确）'),
              (area, '地区'),
              (category, '类型'),
              (exclude, '排除词（空格分隔）'),
            ])
              TextField(
                controller: field.$1,
                decoration: InputDecoration(labelText: field.$2),
              ),
            DropdownButtonFormField<int>(
              initialValue: pages,
              decoration: const InputDecoration(labelText: '每源最大页数'),
              items: [
                for (final value in [1, 3, 5, 10])
                  DropdownMenuItem(value: value, child: Text('$value 页')),
              ],
              onChanged: (value) => setState(() => pages = value!),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, const SearchOptions()),
        child: const Text('重置'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          SearchOptions(
            match: match,
            sort: sort,
            year: year.text,
            area: area.text,
            category: category.text,
            excludeWords: exclude.text,
            maxPages: pages,
          ),
        ),
        child: const Text('应用并搜索'),
      ),
    ],
  );
}
