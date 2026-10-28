import 'dart:convert';
import '../../supervision/presentation/sensitive_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../data/source_share_service.dart';
import '../application/subscription_service.dart';
import '../data/catalog_parser.dart';
import 'catalog_import.dart';
import '../application/source_probe.dart';
import 'source_probe_dialog.dart';

Future<void> importDefaultCatalog(BuildContext context, AppServices services) =>
    perform(context, () async {
      final text = await rootBundle.loadString('assets/tvbox_candidates.json');
      final origin = Uri.parse('https://bbs.qiqiv.cn/thread-5210-1-1.html');
      if (!context.mounted) return;
      await importCatalog(
        context,
        services,
        initial: CatalogPreview(
          origin,
          text,
          const JsonSourceCatalogParser().parse(text, origin),
        ),
      );
    });

Future<void> batchProbeSources(BuildContext context, AppServices services) =>
    perform(context, () async {
      final sources = await services.sources.all();
      if (!context.mounted) return;
      await runSensitive(
        context,
        services.supervision,
        SensitiveOperation.channels,
        () async {
          final probe = SourceProbe(services.sources, services.network);
          final work = probe.run(
            sources,
            concurrency: services.settings.value.probeConcurrency,
            applyPolicy: true,
          );
          final removeCloseHook = services.addCloseHook(() async {
            probe.cancel();
            await work;
          });
          try {
            await showDialog<void>(
              context: context,
              builder: (context) =>
                  SourceProbeDialog(services: services, probe: probe),
            );
          } finally {
            removeCloseHook();
            probe.cancel();
            await work;
            probe.dispose();
          }
        },
      );
    });

Future<void> publishSources(
  BuildContext context,
  AppServices services,
) => perform(context, () async {
  final all = await services.sources.all();
  final sources = all
      .where(
        (s) =>
            s.headers.isEmpty &&
            s.endpoint.query.isEmpty &&
            s.endpoint.userInfo.isEmpty,
      )
      .toList();
  final text = const JsonEncoder.withIndent('  ').convert({
    'sources': [
      for (final s in sources)
        {
          'name': s.name,
          'kind': s.kind,
          'url': s.endpoint.toString(),
          'enabled': false,
        },
    ],
  });
  if (!context.mounted) return;
  final destination = await inputDialog(
    context,
    '发布公开链接',
    ['接受纯文本 POST、返回链接的发布服务 URL'],
    initial: ['https://paste.rs'],
  );
  if (destination == null || !context.mounted) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('确认将公开的内容'),
      content: SizedBox(
        width: 650,
        height: 420,
        child: SingleChildScrollView(
          child: SelectableText(
            '发送到：${Uri.parse(destination.first).host}\n排除 ${all.length - sources.length} 个带请求头或查询参数的来源。发布后链接可被他人访问，删除政策由服务提供者决定。\n\n$text',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('发布公开内容'),
        ),
      ],
    ),
  );
  if (accepted != true) return;
  final link = await publishSourceText(Uri.parse(destination.first), text);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('公开链接已生成'),
      content: SelectableText('$link'),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: '$link'));
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('复制链接'),
        ),
      ],
    ),
  );
});
