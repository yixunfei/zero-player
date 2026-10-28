import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../../supervision/application/content_policy.dart';

/// Displays the effective policy, including supervision's mandatory filter.
final class AdultFilterSetting extends StatelessWidget {
  const AdultFilterSetting({super.key, required this.policy});
  final ContentPolicy policy;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: policy,
    builder: (context, _) => SwitchListTile(
      title: const Text('成人源与内容关键词过滤'),
      subtitle: Text(
        policy.supervision.enabled
            ? '监管模式已强制开启：成人来源不会显示在首页或搜索中。需先验证密码关闭监管模式，才能关闭此过滤。'
            : '过滤成人分类来源及标题/分类中的显式成人关键词，不能识别所有漏标内容。未知分类不代表普通内容。',
      ),
      value: policy.filterAdult,
      onChanged: policy.supervision.enabled
          ? null
          : (value) => perform(
              context,
              () => policy.settings.update({'filterAdult': value}),
            ),
    ),
  );
}
