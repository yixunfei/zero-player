import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/app_services.dart';
import 'music_actions.dart';

const lxSourceNames = [
  'changqing',
  'fish',
  'flower',
  'grass',
  'helloworld',
  'huanyin',
  'huibq',
  'hyw',
  'ikun',
  'jiexiang',
  'juhe',
  'lx',
  'qdy',
  'sixyin',
  'xinghai',
  'yuningxi',
];
Future<void> showLxSources(BuildContext context, AppServices services) =>
    showDialog<void>(
      context: context,
      builder: (_) => _LxSources(services: services),
    );

final class _LxSources extends StatefulWidget {
  const _LxSources({required this.services});
  final AppServices services;
  @override
  State<_LxSources> createState() => _LxSourcesState();
}

final class _LxSourcesState extends State<_LxSources> {
  final _status = <String, String>{};
  final _busy = <String>{};
  late final Future<List<Map>> _catalog = _loadCatalog();
  Future<List<Map>> _loadCatalog() async {
    final raw =
        jsonDecode(
              await rootBundle.loadString(
                'assets/catalogs/music/lx-native-catalog.json',
              ),
            )
            as Map;
    return (raw['sources'] as List).cast<Map>();
  }

  Future<void> _check(String id) async {
    setState(() => _busy.add(id));
    try {
      final uri = switch (id) {
        'uzz' => Uri.parse('https://m.uzz.me/'),
        'musicBox' => Uri.parse('https://mu-jie.cc/musicBox/'),
        'qqmp3' => Uri.parse('https://www.qqmp3.vip/'),
        _ => Uri.https(
          'raw.githubusercontent.com',
          '/pdone/lx-music-source/main/$id/latest.js',
        ),
      };
      final doc = await widget.services.network.get(uri, maxBytes: 1024 * 1024);
      final version = RegExp(r'@version\s+([^\r\n*]+)')
          .firstMatch(doc.text.substring(0, doc.text.length.clamp(0, 4000)))
          ?.group(1)
          ?.trim();
      if (mounted) {
        setState(
          () => _status[id] = version == null
              ? '页面可访问，播放能力需另行验证'
              : '脚本版本 $version；不会执行或自动更新',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _status[id] = '当前请求失败；不代表已接入播放');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('音乐渠道与原生适配'),
    content: SizedBox(
      width: 680,
      height: 500,
      child: ListView(
        children: [
          const Text('推荐与播放分开。以下状态按实际适配分支显示；脚本可访问不等于可播，不执行远程代码。'),
          _site('qqmp3', '米兔音乐', '搜索接口当前返回 403，已从可选播放渠道移除。'),
          _site('musicBox', '枫叶音乐盒', '搜索接口当前返回 502，已从可选播放渠道移除。'),
          const ListTile(
            title: Text('无损音乐下载 · 酷我试听'),
            subtitle: Text('已接入匿名搜索和试听地址；站内下载口令不用于本应用。'),
          ),
          const ListTile(
            title: Text('24bit 无损音乐'),
            subtitle: Text('浏览器可搜索；应用网络请求当前返回 403，暂未列入可播渠道。'),
          ),
          _site('uzz', 'UZZ', '当前返回 403；缺少可验证的接口，不列入可播渠道。'),
          const ListTile(
            title: Text('WFU 一整天的音乐'),
            subtitle: Text('已接入发现音乐中的 WFU 主题推荐；不提取 YouTube 嵌入流。'),
          ),
          const Divider(),
          _openApi(),
          const Divider(),
          const Text('LX 原生适配清单 · 16 项仓库源 + 本地修复包'),
          FutureBuilder<List<Map>>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('音源清单加载失败，请重新打开。');
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                );
              }
              return Column(
                children: [for (final row in snapshot.data!) _source(row)],
              );
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
  Widget _site(String id, String title, String description) => ListTile(
    title: Text(title),
    subtitle: Text('$description\n${_status[id] ?? ''}'),
    trailing: TextButton(
      onPressed: _busy.contains(id) ? null : () => _check(id),
      child: const Text('检查'),
    ),
  );
  Widget _source(Map row) => ListTile(
    title: Text('${row['id']} · ${row['version']}'),
    subtitle: Text(
      '${row['status']}\nSHA-256 ${'${row['sha256']}'.substring(0, 12)}…${_status[row['id']] == null ? '' : '\n${_status[row['id']]}'}',
    ),
    trailing: Wrap(
      children: [
        if ('${row['provider'] ?? ''}'.isNotEmpty)
          TextButton(
            onPressed: () {
              widget.services.musicBrowser.selectProvider(
                row['provider'] as String,
              );
              Navigator.pop(context);
            },
            child: const Text('选择原生分支'),
          ),
        if (row['id'] != 'exclusive-v6')
          TextButton(
            onPressed: _busy.contains(row['id'])
                ? null
                : () => _check(row['id'] as String),
            child: const Text('版本'),
          ),
      ],
    ),
  );
  Widget _openApi() => ListenableBuilder(
    listenable: widget.services.musicOpenApi,
    builder: (context, _) {
      final api = widget.services.musicOpenApi;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LX Open API · 本机状态接口'),
          const Text(
            '默认关闭。提供 /status、/lyric、/lyric-all 和 SSE；暂无歌词时返回空文本。不提供远程控制，也不是歌曲音源。',
          ),
          if (api.address != null) SelectableText(api.address!),
          TextButton(
            onPressed: () => musicAction(
              context,
              api.address == null ? api.start : api.stop,
            ),
            child: Text(api.address == null ? '启用本机状态接口' : '停止本机状态接口'),
          ),
        ],
      );
    },
  );
}
