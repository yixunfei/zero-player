import 'package:flutter/material.dart';
import '../domain/video_source.dart';

/// Shows TCP latency beside the name without changing selector row heights.
final class SourceMenuLabel extends StatelessWidget {
  const SourceMenuLabel(this.source, {super.key});
  final VideoSource source;

  @override
  Widget build(BuildContext context) {
    final ping = source.diagnostics?.tcpMs;
    return Tooltip(
      message:
          'TCP Ping 建连耗时，非 ICMP；不代表视频播放质量。'
          '${source.diagnostics == null ? '' : '\n检测时间：${source.diagnostics!.checkedAt.toLocal()}'}',
      child: Row(
        children: [
          Expanded(
            child: Text(source.displayName, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          Text(
            ping == null ? '— ms' : '$ping ms',
            style: Theme.of(context).textTheme.labelSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
