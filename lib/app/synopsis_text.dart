import 'package:flutter/material.dart';

/// Owns the future across rebuilds. Construct only when the synopsis is visible.
final class SynopsisText extends StatefulWidget {
  const SynopsisText({
    super.key,
    required this.load,
    this.style,
    this.maxLines = 4,
  });
  final Future<String> Function() load;
  final TextStyle? style;
  final int maxLines;
  @override
  State<SynopsisText> createState() => _SynopsisTextState();
}

final class _SynopsisTextState extends State<SynopsisText> {
  late final Future<String> _future = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _future,
    builder: (_, snapshot) => Text(
      snapshot.connectionState != ConnectionState.done
          ? '简介加载中…'
          : snapshot.hasError
          ? '简介暂无法获取，可打开片源详情查看。'
          : snapshot.data ?? '简介暂无法获取',
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
