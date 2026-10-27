import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/platform/file_transfer.dart';
import '../data/m3u_parser.dart';
import '../data/tonkiang_service.dart';
import '../domain/live_channel.dart';
import '../../sources/domain/video_source.dart';

Future<void> showTonkiang(
  BuildContext context,
  AppServices services, {
  String keyword = '',
}) => showDialog<void>(
  context: context,
  builder: (_) => TonkiangDialog(services: services, keyword: keyword),
);

final class TonkiangDialog extends StatefulWidget {
  const TonkiangDialog({super.key, required this.services, this.keyword = ''});
  final AppServices services;
  final String keyword;
  @override
  State<TonkiangDialog> createState() => _TonkiangDialogState();
}

final class _TonkiangDialogState extends State<TonkiangDialog> {
  final query = TextEditingController();
  final selected = <String>{};
  final results = <LiveChannel>[];
  CancellationToken? token;
  Uri? nextPage;
  String? error;
  bool busy = false;
  String searched = '';

  @override
  void initState() {
    super.initState();
    query.text = widget.keyword;
  }

  @override
  void dispose() {
    token?.cancel();
    query.dispose();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    token?.cancel();
    final current = CancellationToken();
    token = current;
    setState(() {
      busy = true;
      error = null;
    });
    if (!more) {
      searched = query.text.trim();
      results.clear();
      selected.clear();
      nextPage = null;
    }
    try {
      final page = await TonkiangService(
        widget.services.network,
      ).search(searched, page: more ? nextPage : null, cancellation: current);
      if (!mounted || current.isCancelled) return;
      setState(() {
        final ids = results.map((c) => c.id).toSet();
        results.addAll(
          page.channels.where((c) => ids.add(c.id)).take(200 - results.length),
        );
        nextPage = results.length >= 200 ? null : page.nextPage;
      });
    } catch (e) {
      if (mounted && !current.isCancelled) setState(() => error = '$e');
    } finally {
      if (mounted && token == current) setState(() => busy = false);
    }
  }

  Future<void> _paste({bool file = false}) => perform(context, () async {
    final text = file
        ? await FileTransfer.readText(maxBytes: 2 * 1024 * 1024)
        : (await Clipboard.getData('text/plain'))?.text;
    if (text == null) return;
    final parsed = TonkiangService.parseCopiedText(text, query.text.trim());
    if (!mounted) return;
    setState(() {
      results.clear();
      results.addAll(parsed);
      selected.clear();
      error = null;
      nextPage = null;
      searched = query.text.trim();
    });
  });

  Future<void> _import() async {
    setState(() => busy = true);
    await perform(context, () async {
      final channels = results.where((c) => selected.contains(c.id)).toList();
      final uri = TonkiangService.searchUrl(
        searched.isEmpty ? query.text.trim() : searched,
      );
      final existing = (await widget.services.live.channels()).where(
        (c) => c.listId.isNotEmpty && c.listId == _listId(uri),
      );
      await widget.services.live.importText(
        'Tonkiang · ${searched.isEmpty ? query.text.trim() : searched}',
        uri,
        exportM3u([...existing, ...channels]),
      );
      if (mounted) {
        message(context, '已导入 ${channels.length} 条线路，可在直播页测活');
        Navigator.pop(context);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  String _listId(Uri uri) => stableId(uri.toString());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('在线电视 IPTV · Tonkiang'),
    content: SizedBox(
      width: 680,
      height: 480,
      child: Column(
        children: [
          TextField(
            controller: query,
            enabled: !busy,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(labelText: '搜索频道，例如 CCTV1'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: busy ? null : _search,
                child: const Text('搜索'),
              ),
              TextButton(
                onPressed: busy ? null : () => _paste(),
                child: const Text('粘贴结果文字 / HTML'),
              ),
              TextButton(
                onPressed: busy ? null : () => _paste(file: true),
                child: const Text('文件导入'),
              ),
              TextButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: TonkiangService.searchUrl(query.text).toString(),
                  ),
                ),
                child: const Text('复制原站搜索链接'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
          const Text('按需搜索并选择线路；验证页不会被当作频道导入。媒体可用性请导入后测活。'),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, i) {
                final channel = results[i];
                return CheckboxListTile(
                  title: Text(channel.name),
                  subtitle: Text('${channel.urls.first}'),
                  value: selected.contains(channel.id),
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            selected.add(channel.id);
                          } else {
                            selected.remove(channel.id);
                          }
                        }),
                );
              },
            ),
          ),
          if (nextPage != null)
            TextButton(
              onPressed: busy ? null : () => _search(more: true),
              child: const Text('加载下一页'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          token?.cancel();
          Navigator.pop(context);
        },
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: busy || selected.isEmpty ? null : _import,
        child: Text('导入 ${selected.length} 条'),
      ),
    ],
  );
}
