import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../discovery/data/recommendation_repository.dart';
import '../../sources/domain/video_source.dart';

final class HomePreferences extends StatefulWidget {
  const HomePreferences({super.key, required this.services});
  final AppServices services;
  @override
  State<HomePreferences> createState() => _HomePreferencesState();
}

final class _HomePreferencesState extends State<HomePreferences> {
  late Future<List<VideoSource>> _sources;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sources = widget.services.sources.all();
    _changes = widget.services.sources.changes.listen((_) {
      if (mounted) {
        setState(() {
          _sources = widget.services.sources.all();
        });
      }
    });
  }

  @override
  void didUpdateWidget(HomePreferences oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services != widget.services) {
      unawaited(_changes?.cancel());
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<VideoSource>>(
    future: _sources,
    builder: (context, snapshot) {
      final settings = widget.services.settings.value;
      final sources = (snapshot.data ?? []).where(
        (s) =>
            s.enabled &&
            !s.suppressed &&
            (!settings.filterAdult || s.classification != 'adult'),
      );
      final choices = <String, String>{
        '': recommendationNames[settings.recommendation] ?? '精选推荐',
        for (final source in sources) source.id: source.displayName,
      };
      if (!choices.containsKey(settings.homeChannel)) {
        choices[settings.homeChannel] = '已失效的默认频道（启动时回退）';
      }
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              key: ValueKey('home-${settings.homeChannel}'),
              initialValue: settings.homeChannel,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '默认开屏频道'),
              items: choices.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: snapshot.hasData
                  ? (value) => perform(
                      context,
                      () => widget.services.settings.update({
                        'homeChannel': value ?? '',
                      }),
                    )
                  : null,
            ),
          ),
          SwitchListTile(
            title: const Text('开屏使用分类聚合'),
            subtitle: const Text('按所选频道支持的分类轮流加载，最多 6 类、240 部；首页也可临时切换'),
            value: settings.homeLayout == 'aggregate',
            onChanged: (value) => perform(
              context,
              () => widget.services.settings.update({
                'homeLayout': value ? 'aggregate' : 'single',
              }),
            ),
          ),
        ],
      );
    },
  );
}
