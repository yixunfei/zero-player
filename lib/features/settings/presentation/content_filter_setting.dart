import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../app/setting_dropdown.dart';
import '../../../media/content_filter/filter_strategy.dart';
import '../../supervision/presentation/sensitive_action.dart';
import 'filter_resources_dialog.dart';

final class ContentFilterSetting extends StatelessWidget {
  const ContentFilterSetting({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        title: const Text('播放中特征跳过（流畅优先）'),
        subtitle: const Text(
          '基础音画指纹在本地运行，无需下载模型。标记一次后，按频道或全剧范围在不同时间点识别相同内容。'
          '无样本时仅保留本集标记和显式清单过滤，不自动识别未知广告。'
          '检测可能晚于播放或误判，不保证屏蔽全部内容；支持撤销跳过，不覆盖直播。下次打开视频生效。',
        ),
        value: services.settings.value.contentFilter,
        onChanged: (value) => perform(
          context,
          () => runSensitive(
            context,
            services.supervision,
            SensitiveOperation.settings,
            () => services.settings.update({'contentFilter': value}),
            needed: !value,
          ),
        ),
      ),
      _strategySelector(context),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '保守：高置信度自动跳过。积极：允许轻微内容变化，可能增加误跳。提示：命中后可选择跳过或忽略。关键词始终先确认，不受自动策略影响。显式本集区间由片段管理单独控制。',
        ),
      ),
      ListTile(
        title: const Text('默认常见词'),
        subtitle: const Text(
          '澳门 / 新葡京 / 缅北 / 赌场 / 真人 / 博彩 / www*。这些词也可能出现在正常内容中，命中只提示，确认后才跳过。语音检测需轻量资源，画面网址需可选 OCR。',
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SettingDropdown<int>(
          value: services.settings.value.filterSkipSeconds,
          label: '默认跳过时长',
          items: [
            for (final seconds in ({
              5,
              10,
              15,
              20,
              30,
              45,
              60,
              90,
              120,
              services.settings.value.filterSkipSeconds,
            }.toList()..sort()))
              DropdownMenuItem(value: seconds, child: Text('$seconds 秒')),
          ],
          onChanged: (value) {
            if (value != null) {
              perform(
                context,
                () => runSensitive(
                  context,
                  services.supervision,
                  SensitiveOperation.settings,
                  () => services.settings.update({'filterSkipSeconds': value}),
                ),
              );
            }
          },
        ),
      ),
      ListTile(
        title: const Text('常见词语音 / OCR 可选资源'),
        subtitle: const Text('手动下载、启停和清理，不随基础包安装'),
        trailing: const Icon(Icons.download_outlined),
        onTap: () => showFilterResources(context, services),
      ),
    ],
  );
  Widget _strategySelector(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: SettingDropdown<FilterStrategy>(
      value: FilterStrategy.parse(services.settings.value.filterStrategy),
      label: '内容特征处理策略',
      items: [
        for (final strategy in FilterStrategy.values)
          DropdownMenuItem(value: strategy, child: Text(strategy.label)),
      ],
      onChanged: (strategy) {
        if (strategy == null) return;
        perform(
          context,
          () => runSensitive(
            context,
            services.supervision,
            SensitiveOperation.settings,
            () => services.settings.update({'filterStrategy': strategy.name}),
          ),
        );
      },
    ),
  );
}
