import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../../supervision/application/content_policy.dart';
import '../../supervision/application/installation_access.dart';
import '../../supervision/presentation/adult_access_dialog.dart';

/// Displays the effective policy, including supervision's mandatory filter.
final class AdultFilterSetting extends StatefulWidget {
  const AdultFilterSetting({
    super.key,
    required this.policy,
    required this.access,
  });
  final ContentPolicy policy;
  final InstallationAccess access;
  @override
  State<AdultFilterSetting> createState() => _AdultFilterSettingState();
}

final class _AdultFilterSettingState extends State<AdultFilterSetting> {
  bool _busy = false;
  ContentPolicy get policy => widget.policy;

  Future<void> _change(bool value) => perform(context, () async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!value && !await verifyAdultFilterAccess(context, widget.access)) {
        return;
      }
      if (!mounted) return;
      await policy.settings.update({'filterAdult': value});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

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
      onChanged: policy.supervision.enabled || _busy ? null : _change,
    ),
  );
}
