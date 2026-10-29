import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../media/content_filter/optional_resources.dart';
import '../../../media/content_filter/local_models.dart';
import '../../../media/content_filter/keyword_models.dart';
import '../../supervision/presentation/sensitive_action.dart';

Future<void> showFilterResources(BuildContext context, AppServices services) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ResourcesDialog(services),
    );

final class _ResourcesDialog extends StatefulWidget {
  const _ResourcesDialog(this.services);
  final AppServices services;
  @override
  State<_ResourcesDialog> createState() => _ResourcesDialogState();
}

final class _ResourcesDialogState extends State<_ResourcesDialog> {
  final _installed = <Enhancement, bool>{};
  CancellationToken? _token;
  bool _busy = false;
  String _status = '';
  double? _progress;
  OptionalResources get _resources => widget.services.contentFilter.resources;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    for (final kind in Enhancement.values) {
      final installed = await _resources.installed(kind);
      if (mounted) setState(() => _installed[kind] = installed);
    }
  }

  Future<void> _download(Enhancement kind) async {
    if (_busy) return;
    final token = _token = CancellationToken();
    setState(() {
      _busy = true;
      _status = '准备下载';
      _progress = null;
    });
    try {
      await _resources.download(
        kind,
        token,
        progress: (name, received, total) {
          if (mounted) {
            setState(() {
              _status = '正在下载 $name';
              _progress = received / total;
            });
          }
        },
      );
      if (mounted) setState(() => _status = '安装完成，可启用此增强识别');
    } catch (error) {
      if (mounted) {
        setState(() => _status = token.isCancelled ? '下载已取消' : '$error');
      }
    } finally {
      _token = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
        await _refresh();
      }
    }
  }

  Future<void> _change(
    Enhancement kind, {
    bool? enable,
    bool remove = false,
  }) async {
    if (_busy) return;
    final services = widget.services;
    final key = switch (kind) {
      Enhancement.keywords => 'filterKeywords',
      Enhancement.ocr => 'filterOcr',
      Enhancement.asr => 'filterAsr',
    };
    setState(() => _busy = true);
    try {
      await runSensitive(
        context,
        services.supervision,
        SensitiveOperation.settings,
        () async {
          if (enable == true) {
            final token = CancellationToken();
            await _resources.runtime.ensure(token);
            if (kind == Enhancement.keywords) {
              await _resources.keywords.ensure(token);
            } else {
              await _resources.models.ensure(
                token,
                ocr: kind == Enhancement.ocr,
                asr: kind == Enhancement.asr,
              );
            }
          }
          if (remove) {
            // A failed resource removal must not silently disable a working filter.
            final result = await _resources.remove(kind);
            await services.settings.update({key: false});
            if (mounted) setState(() => _status = result);
          } else {
            await services.settings.update({key: enable!});
            if (mounted) setState(() => _status = '设置已保存，下次打开视频生效');
          }
        },
        needed: remove || enable == false,
      );
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('可选增强识别资源'),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '基础声画特征匹配不需要模型。仅在这里点击下载才会联网安装；播放不会自动下载。'
              '下载来源为 GitHub、Hugging Face 和 pub.dev，文件经固定 SHA-256 校验，仅在本机识别。',
            ),
            const SizedBox(height: 8),
            Text(
              '首次增强安装另需共享 CPU 运行库约 '
              '${(_resources.runtime.package.archive.bytes / 1048576).toStringAsFixed(1)} MiB 下载。',
            ),
            const Text(
              'OCR 资源遵循 Apache-2.0；SenseVoice 权重遵循 FunASR 模型许可，商业用途请查看关于页的第三方许可。',
            ),
            for (final kind in Enhancement.values) _tile(kind),
            if (_busy)
              Padding(
                padding: const EdgeInsets.all(8),
                child: LinearProgressIndicator(value: _progress),
              ),
            if (_status.isNotEmpty) Text(_status),
          ],
        ),
      ),
    ),
    actions: [
      if (_token != null)
        TextButton(
          onPressed: () => _token?.cancel(),
          child: const Text('取消下载'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  Widget _tile(Enhancement kind) {
    final ocr = kind == Enhancement.ocr;
    final keywords = kind == Enhancement.keywords;
    final settings = widget.services.settings.value;
    final enabled = keywords
        ? settings.filterKeywords
        : ocr
        ? settings.filterOcr
        : settings.filterAsr;
    final installed = _installed[kind] == true;
    final bytes = keywords
        ? KeywordModels.totalBytes
        : LocalModels.selected(
            ocr: ocr,
            asr: !ocr,
          ).fold(0, (sum, a) => sum + a.bytes);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                keywords
                    ? '常见词语音检测（推荐）'
                    : ocr
                    ? 'OCR：画面大字主题词'
                    : 'ASR：完整语音识别（高耗能）',
              ),
              subtitle: Text(
                '模型约 ${(bytes / 1048576).toStringAsFixed(1)} MiB · ${installed ? '已安装' : '未安装'}'
                '${keywords ? '；首次模型下载约 ${(KeywordModels.archive.bytes / 1048576).toStringAsFixed(1)} MiB，安装仅保留量化文件' : ''}',
              ),
              value: enabled,
              onChanged: _busy || (!installed && !enabled)
                  ? null
                  : (value) => _change(kind, enable: value),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _download(kind),
                  child: Text(installed ? '校验 / 修复资源' : '手动下载'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _change(kind, remove: true),
                  child: const Text('删除 / 清理资源'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
