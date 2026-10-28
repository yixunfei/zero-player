import 'package:flutter/material.dart';
import '../domain/live_channel.dart';

class LiveChannelDetails extends StatelessWidget {
  const LiveChannelDetails({super.key, required this.channel});
  final LiveChannel channel;
  String _values(Iterable<String> values) {
    final text = values.where((v) => v.isNotEmpty).toSet().join(' / ');
    return text.isEmpty ? '未知' : text;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('分类：${_values(channel.categories)}'),
      Text('语言：${_values(channel.languages)}'),
      Text(
        '地区：${_values(channel.entries.expand((c) => c.metadata.countries))}',
      ),
      Text('分辨率：${_values(channel.resolutions)}'),
      if (channel.health.latencyMs != null)
        Text('检测延迟：${channel.health.latencyMs} ms（首媒体数据）'),
      const Text('直播时长：无固定时长'),
      Text('节目表标识：${_values(channel.entries.map((c) => c.tvgId))}'),
      const Text(
        '分类 / 地区来自订阅；语言 / 分辨率来自订阅或所测 HLS 清单，非解码验证。',
        style: TextStyle(fontSize: 12),
      ),
      if (channel.entries.length > 1)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('各来源详情'),
          children: [
            for (final entry in channel.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(entry.listName),
                subtitle: Text(
                  '${entry.health.availabilityLabel}\n分辨率：${_values(entry.resolutions)} · 语言：${_values(entry.languages)}',
                ),
              ),
          ],
        ),
    ],
  );
}
