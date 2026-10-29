import 'package:flutter/material.dart' hide SearchController;
import '../application/search_controller.dart';
import '../../sources/presentation/block_source_button.dart';

class SearchStatusPanel extends StatelessWidget {
  const SearchStatusPanel({super.key, required this.controller});
  final SearchController controller;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (controller.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(controller.error!),
        ),
      if (controller.statuses.isNotEmpty)
        ExpansionTile(
          title: Text(
            '${controller.groups.length} 部作品 · 已完成 ${controller.completed}/${controller.statuses.length} 个来源',
          ),
          children: [
            if (!controller.loading && controller.failedSources.isNotEmpty)
              TextButton.icon(
                onPressed: controller.retryFailed,
                icon: const Icon(Icons.refresh),
                label: Text(
                  '重试失败 / 未完成来源 (${controller.failedSources.length})',
                ),
              ),
            SizedBox(
              height: 140,
              child: ListView(
                primary: false,
                children: [
                  for (final status in controller.statuses.entries)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      dense: true,
                      title: Text(
                        '${controller.sourceLabels[status.key] ?? '未知渠道'} · ${controller.sourceNames[status.key] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${status.value}${controller.latencies[status.key] == null ? '' : ' · ${controller.latencies[status.key]} ms'}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: controller.failedSources.contains(status.key)
                          ? BlockSourceButton(
                              name: controller.sourceNames[status.key] ?? '此来源',
                              compact:
                                  MediaQuery.sizeOf(context).shortestSide < 600,
                              onBlock: () => controller.blockSource(status.key),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
    ],
  );
}
