import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../supervision/presentation/sensitive_action.dart';

Future<void> showAwesomeZhuijuSync(
  BuildContext context,
  AppServices services,
) => showDialog<void>(
  context: context,
  builder: (_) => _AwesomeZhuijuDialog(services),
);

final class _AwesomeZhuijuDialog extends StatefulWidget {
  const _AwesomeZhuijuDialog(this.services);
  final AppServices services;
  @override
  State<_AwesomeZhuijuDialog> createState() => _AwesomeZhuijuDialogState();
}

final class _AwesomeZhuijuDialogState extends State<_AwesomeZhuijuDialog> {
  late Future<Map?> _last = widget.services.awesomeZhuiju.lastResult();
  CancellationToken? _token;
  String? _status;

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_token != null) return;
    final token = CancellationToken();
    setState(() {
      _token = token;
      _status = null;
    });
    try {
      await runSensitive(
        context,
        widget.services.supervision,
        SensitiveOperation.channels,
        () async {
          final report = await widget.services.awesomeZhuiju.sync(
            token,
            progress: (value) {
              if (mounted) setState(() => _status = value);
            },
          );
          if (mounted) {
            setState(() {
              _last = Future.value(report);
              _status = '同步完成';
            });
          }
        },
      );
    } on RequestCancelled {
      if (mounted) setState(() => _status = '已取消同步');
    } on FormatException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) setState(() => _status = '同步失败，已保留上次成功结果');
    } finally {
      if (mounted) setState(() => _token = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('awesome-zhuiju-free'),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('手动获取上游目录。跳过重复和未标记可用的入口，通过实际解码验证后新增来源。'),
          const SizedBox(height: 12),
          FutureBuilder<Map?>(
            future: _last,
            builder: (context, snapshot) {
              final report = snapshot.data;
              if (report == null) return const Text('尚无同步记录');
              final checkedAt = DateTime.tryParse(
                '${report['checkedAt']}',
              )?.toLocal();
              final date = checkedAt == null
                  ? ''
                  : MaterialLocalizations.of(
                      context,
                    ).formatShortDate(checkedAt);
              return Text(
                '上次同步 $date\n'
                '新增 ${report['videosAdded']} 个点播源、${report['channelsAdded']} 个直播频道\n'
                '跳过 ${report['duplicates']} 个重复项、${report['upstreamSkipped']} 个未通过上游筛选的入口'
                '${report['playlistsDeferred'] == 0 ? '' : '\n有 ${report['playlistsDeferred']} 份候选列表待后续检查'}',
              );
            },
          ),
          if (_status != null) ...[const SizedBox(height: 12), Text(_status!)],
          if (_token != null) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _token == null
            ? () => Navigator.pop(context)
            : _token!.cancel,
        child: Text(_token == null ? '关闭' : '取消同步'),
      ),
      FilledButton(
        onPressed: _token == null ? _sync : null,
        child: const Text('检查并同步'),
      ),
    ],
  );
}
