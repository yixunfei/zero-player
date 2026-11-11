import 'package:flutter/material.dart';
import '../domain/live_channel.dart';

class LiveChannelDetails extends StatelessWidget {
  const LiveChannelDetails({
    super.key,
    required this.channel,
    required this.onDisableSource,
  });
  final LiveChannel channel;
  final Future<bool> Function(List<LiveChannel>) onDisableSource;
  String _values(Iterable<String> values) {
    final text = values.where((v) => v.isNotEmpty).toSet().join(' / ');
    return text.isEmpty ? '未知' : text;
  }

  @override
  Widget build(BuildContext context) {
    final sources = <String, List<LiveChannel>>{};
    for (final entry in channel.entries) {
      if (entry.listId.isEmpty) continue;
      sources.putIfAbsent(entry.listId, () => []).add(entry);
    }
    final preferredUrl = channel.health.enabled
        ? channel.playbackUrls.firstOrNull
        : null;
    final preferredSource = channel.entries
        .where((entry) => entry.playbackUrls.contains(preferredUrl))
        .firstOrNull
        ?.listId;
    return Column(
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
        if (sources.isNotEmpty) ...[
          const Divider(),
          Text('频道渠道', style: Theme.of(context).textTheme.titleSmall),
          for (final entries in sources.values)
            _source(
              entries,
              preferred: entries.first.listId == preferredSource,
            ),
        ],
      ],
    );
  }

  Widget _source(
    List<LiveChannel> entries, {
    required bool preferred,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entries.first.sourceLabel),
        Text(
          [
            if (preferred) '首选渠道',
            _values(entries.map((e) => e.health.availabilityLabel)),
          ].join(' · '),
        ),
        Text(
          '分辨率：${_values(entries.expand((e) => e.resolutions))} · 语言：${_values(entries.expand((e) => e.languages))}',
        ),
        if (entries.any((e) => e.health.enabled))
          TextButton.icon(
            onPressed: () => onDisableSource(entries),
            icon: const Icon(Icons.block),
            label: const Text('停用此渠道'),
          ),
      ],
    ),
  );
}
