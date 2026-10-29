import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Explicit bounds avoid intrinsic measurement of scrollables/LayoutBuilder.
final class SourceChoicesDialog extends StatelessWidget {
  const SourceChoicesDialog({
    super.key,
    required this.title,
    required this.child,
  });
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.size.width < 600 ? 12.0 : 24.0;
    final height = math.min(
      600.0,
      math.max(
        0.0,
        media.size.height -
            media.viewInsets.vertical -
            media.padding.vertical -
            inset * 2,
      ),
    );
    return Dialog(
      insetPadding: EdgeInsets.all(inset),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 640,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const CloseButton(),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
            const Divider(height: 1),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
