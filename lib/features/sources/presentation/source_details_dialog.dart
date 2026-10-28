import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../core/network/request_trace.dart';
import '../application/source_probe.dart';
import '../domain/video_source.dart';
import 'source_favorite_button.dart';

Future<void> showSourceDetails(
  BuildContext context,
  AppServices services,
  VideoSource source,
) => showDialog<void>(
  context: context,
  builder: (_) => SourceDetailsDialog(services: services, source: source),
);

final class SourceDetailsDialog extends StatefulWidget {
  const SourceDetailsDialog({
    super.key,
    required this.services,
    required this.source,
  });
  final AppServices services;
  final VideoSource source;
  @override
  State<SourceDetailsDialog> createState() => _SourceDetailsDialogState();
}

final class _SourceDetailsDialogState extends State<SourceDetailsDialog> {
  late VideoSource _source = widget.source;
  late final _probe = SourceProbe(
    widget.services.sources,
    widget.services.network,
  );
  late final StreamSubscription<void> _changes;
  late final void Function() _removeHook;
  Future<void>? _pending;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.services.sources.changes.listen(
      (_) => unawaited(_reload()),
    );
    _removeHook = widget.services.addCloseHook(_stop);
  }

  Future<void> _reload() async {
    final source = await widget.services.sources.find(widget.source.id);
    if (mounted && source != null) setState(() => _source = source);
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _pending = _probe
        .run([_source], concurrency: 1, applyPolicy: true)
        .catchError((Object _) {
          if (mounted) setState(() => _error = '诊断未完成，请稍后重试');
        });
    await _pending;
    if (mounted) {
      await _reload();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    _probe.cancel();
    await _pending;
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    unawaited(
      _stop().whenComplete(() {
        _removeHook();
        _probe.dispose();
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Expanded(child: Text(_source.displayName)),
        SourceFavoriteButton(
          source: _source,
          repository: widget.services.sources,
        ),
      ],
    ),
    content: SizedBox(
      width: 680,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            _field(
              '状态',
              '${_source.suppressed
                      ? '已移除'
                      : _source.enabled
                      ? '已启用'
                      : '已停用'} · '
                  '${_source.diagnostics?.label ?? (_source.apiOk ? '接口可用' : '尚未诊断')}',
            ),
            _field('接口网址', safeDiagnosticUrl(_source.endpoint)),
            if (_source.homepage != null)
              _field('网站主页', safeDiagnosticUrl(_source.homepage!)),
            _field('类型 / 端口', '${_source.kind} / ${_source.endpoint.port}'),
            _field(
              'IP 地址',
              _source.diagnostics?.addresses.join('\n') ?? '尚未解析',
            ),
            _field('TCP Ping', _ms(_source.diagnostics?.tcpMs)),
            _field('DNS 耗时', _ms(_source.diagnostics?.dnsMs)),
            _field('接口耗时', _ms(_source.latencyMs)),
            const Text('TCP Ping 为建立 TCP 连接的耗时，非 ICMP。接口成功不代表媒体已验证。'),
            if (_source.diagnostics != null) ...[
              _field(
                '检测时间',
                _source.diagnostics!.checkedAt.toLocal().toString(),
              ),
              if (_source.diagnostics!.dnsEvidence.isNotEmpty)
                _field('域名证据', _source.diagnostics!.dnsEvidence.join('\n')),
            ],
            _field(
              '配置请求头',
              const JsonEncoder.withIndent(
                '  ',
              ).convert(safeDiagnosticHeaders(_source.headers)),
            ),
            for (final request
                in _source.diagnostics?.requests ?? <Map<String, Object?>>[])
              _request(request),
            if (_source.diagnostics == null) const Text('点击“刷新诊断”获取最新网络信息。'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? _probe.cancel : _refresh,
        child: Text(_busy ? '停止诊断' : '刷新诊断'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  String _ms(int? value) => value == null ? '未获取' : '$value ms';
  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        SelectableText(value.isEmpty ? '未获取' : value),
      ],
    ),
  );
  Widget _request(Map<String, Object?> request) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(
      '${request['method']} · HTTP ${request['status'] ?? '未响应'} · ${request['elapsedMs']} ms',
    ),
    subtitle: Text(
      '${request['url']}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    children: [
      _field(
        '请求 / 响应（敏感凭证已隐藏）',
        const JsonEncoder.withIndent('  ').convert(request),
      ),
    ],
  );
}
