import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> copyBookLink(BuildContext context, Uri uri) async {
  var message = '网页链接已复制';
  try {
    await Clipboard.setData(ClipboardData(text: '$uri'));
  } on PlatformException {
    message = '无法访问系统剪贴板';
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

final class BookLinkButton extends StatelessWidget {
  const BookLinkButton({super.key, required this.label, required this.uri});
  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    icon: const Icon(Icons.link),
    onPressed: () => copyBookLink(context, uri),
  );
}
