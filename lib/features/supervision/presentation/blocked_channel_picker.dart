import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../domain/supervision_rules.dart';

Future<BlockedChannel?> pickBlockedChannel(
  BuildContext context,
  AppServices services,
) => showDialog<BlockedChannel>(
  context: context,
  builder: (_) => _ChannelPicker(services),
);

final class _ChannelPicker extends StatefulWidget {
  const _ChannelPicker(this.services);
  final AppServices services;
  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

final class _ChannelPickerState extends State<_ChannelPicker> {
  String _kind = 'vod', _query = '';
  late Future<List<BlockedChannel>> _items = _load();
  Future<List<BlockedChannel>> _load() async {
    final services = widget.services, policy = widget.services.contentPolicy;
    if (_kind == 'vod') {
      return [
        for (final source in await services.sources.all(
          includeSuppressed: true,
        ))
          BlockedChannel(policy.sourceKey(source), source.displayName),
      ];
    }
    final radio = _kind == 'radio';
    final channels = radio
        ? (await services.radio.load(includeBlocked: true)).stations
        : await services.live.channels(includeBlocked: true);
    return {
      for (final c in channels)
        policy.channelKey(c.name, radio: radio): BlockedChannel(
          policy.channelKey(c.name, radio: radio),
          c.name,
        ),
    }.values.toList();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择屏蔽频道'),
    content: SizedBox(
      width: 600,
      height: 450,
      child: Column(
        children: [
          DropdownButton<String>(
            value: _kind,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'vod', child: Text('点播来源')),
              DropdownMenuItem(value: 'live', child: Text('直播频道')),
              DropdownMenuItem(value: 'radio', child: Text('广播电台')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _kind = value;
                  _items = _load();
                });
              }
            },
          ),
          TextField(
            decoration: const InputDecoration(labelText: '搜索频道名称'),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LoadView(
              future: _items,
              builder: (items) {
                final visible = items
                    .where((c) => c.label.toLowerCase().contains(_query))
                    .toList();
                if (visible.isEmpty) {
                  return const Center(child: Text('没有匹配频道；直播或广播需先加载订阅'));
                }
                return ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    return ListTile(
                      title: Text(item.label),
                      trailing: const Icon(Icons.block),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
}
