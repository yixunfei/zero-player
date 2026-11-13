import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_services.dart';
import '../features/books/domain/book.dart';
import '../features/books/presentation/book_page_route.dart';
import '../features/books/presentation/book_sources_page.dart';
import '../features/live/presentation/live_subscriptions_dialog.dart';
import '../features/radio/presentation/radio_subscriptions_dialog.dart';
import '../features/music/presentation/lx_sources_dialog.dart';

Future<void> showModuleSources(
  BuildContext context,
  AppServices services,
  String location,
) async {
  var module = location;
  const kinds = {
    '/': '影院',
    '/live': '直播',
    '/radio': '广播',
    '/music': '音乐',
    '/reading': '阅读',
    '/audiobooks': '听书',
  };
  if (!kinds.containsKey(module)) {
    module =
        await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('选择渠道类型'),
            children: [
              for (final item in kinds.entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, item.key),
                  child: Text(item.value),
                ),
            ],
          ),
        ) ??
        '';
    if (!context.mounted || module.isEmpty) return;
  }
  switch (module) {
    case '/reading':
    case '/audiobooks':
      await Navigator.of(context, rootNavigator: true).push(
        BookPageRoute<void>(
          builder: (_) => BookSourcesPage(
            services: services,
            kind: module == '/reading' ? BookKind.text : BookKind.audio,
          ),
        ),
      );
    case '/live':
      await showDialog<void>(
        context: context,
        builder: (_) => LiveSubscriptionsDialog(services: services),
      );
    case '/radio':
      await showDialog<void>(
        context: context,
        builder: (_) => RadioSubscriptionsDialog(repository: services.radio),
      );
    case '/music':
      await showLxSources(context, services);
    default:
      await context.push('/sources');
  }
}
