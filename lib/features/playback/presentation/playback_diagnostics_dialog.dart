import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/widgets.dart';
import '../../../core/platform/file_transfer.dart';
import '../application/playback_controller.dart';

Future<void> showPlaybackDiagnostics(
  BuildContext context,
  PlaybackController controller,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final report = controller.diagnosticReport();
    return AlertDialog(
      title: const Text('播放与过滤诊断'),
      content: SizedBox(
        width: 620,
        height: 420,
        child: SingleChildScrollView(child: SelectableText(report)),
      ),
      actions: [
        TextButton(
          onPressed: () => perform(context, () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('诊断已复制')));
            }
          }),
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => perform(
            context,
            () => FileTransfer.saveText('zero-player-diagnostics.txt', report),
          ),
          child: const Text('保存文本'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  },
);
