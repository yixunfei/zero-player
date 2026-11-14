import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/qidian_saved_page.dart';
import 'book_links.dart';

Future<List<int>?> pickQidianBrowserPage(
  BuildContext context,
  Uri uri, {
  required bool Function() allowed,
}) async {
  if (!allowed()) return null;
  final choose = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('导入浏览器网页'),
      content: const Text(
        '在浏览器打开对应的起点页面。显示作品后，另存为「网页，全部」或「单个文件」，再回到这里选择 HTML 或 MHTML 文件。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            if (!allowed()) return;
            try {
              if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                return;
              }
            } on Exception {
              // The same page can still be opened using its copied address.
            }
            if (dialogContext.mounted && allowed()) {
              await copyBookLink(context, uri);
            }
          },
          child: const Text('在浏览器打开起点'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('选择网页文件'),
        ),
      ],
    ),
  );
  if (choose != true || !context.mounted || !allowed()) return null;
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: '起点网页',
        extensions: ['html', 'htm', 'mhtml', 'mht'],
        mimeTypes: [
          'text/html',
          'multipart/related',
          'message/rfc822',
          'application/octet-stream',
        ],
      ),
    ],
  );
  if (file == null || !allowed()) return null;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (!allowed()) return null;
    if (bytes.length + chunk.length > maxQidianSavedPageBytes) {
      throw const FormatException('网页文件超过 16 MiB');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}
