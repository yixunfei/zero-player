import 'package:flutter/material.dart';

import '../domain/book.dart';
import '../domain/legado_source.dart';

String bookCategoryLabel(LegadoCategory item, int index) =>
    item.title.isEmpty ? (index == 0 ? '推荐' : '分类 ${index + 1}') : item.title;

Future<LegadoCategory?> showBookCategoryPicker(
  BuildContext context,
  List<LegadoCategory> categories,
  LegadoCategory? selected,
) {
  var query = '';
  return showDialog<LegadoCategory>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        final key = bookIdentity(query);
        final visible = categories.indexed
            .where(
              (row) =>
                  key.isEmpty ||
                  bookIdentity(bookCategoryLabel(row.$2, row.$1)).contains(key),
            )
            .toList();
        return AlertDialog(
          title: const Text('渠道分类'),
          content: SizedBox(
            width: 480,
            height: MediaQuery.sizeOf(context).height * .48,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '筛选分类',
                  ),
                  onChanged: (value) => update(() => query = value),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('没有匹配分类'))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final (original, item) = visible[index];
                            return ListTile(
                              title: Text(bookCategoryLabel(item, original)),
                              selected: item == selected,
                              trailing: item == selected
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () => Navigator.pop(context, item),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
