import 'package:flutter/material.dart';

final class ContentBlockedDialog extends StatelessWidget {
  const ContentBlockedDialog({super.key, required this.supervised});
  final bool supervised;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('禁止访问'),
    content: Text(
      supervised
          ? '监管设置人已禁止访问此内容。频道、节目和网站信息均已隐藏，请联系监管设置人。'
          : '此内容已被成人过滤屏蔽，频道、节目和网站信息均已隐藏。',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
