import 'package:flutter/material.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/presentation/disclaimer_dialog.dart';

Future<void> showNavigationGuide(
  BuildContext context,
  SettingsController settings,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _NavigationGuide(settings: settings),
);

final class _NavigationGuide extends StatefulWidget {
  const _NavigationGuide({required this.settings});
  final SettingsController settings;
  @override
  State<_NavigationGuide> createState() => _NavigationGuideState();
}

final class _NavigationGuideState extends State<_NavigationGuide> {
  bool _saving = false;
  String? _error;

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.settings.update({'navigationGuideSeen': true});
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '引导状态保存失败，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      icon: Icon(Icons.menu_open, color: Theme.of(context).colorScheme.primary),
      title: const Text('从这里开始探索'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _tip(
              Icons.menu,
              '左上角「菜单」',
              '点击即可打开导航，进入发现、搜索、直播、记录、下载和设置。向下滚动时，左上角仍保留菜单入口。',
            ),
            _tip(Icons.search, '主页中央搜索', '通过醒目的搜索框查找影片、剧集或动漫；键盘也可使用 Ctrl+K。'),
            _tip(
              Icons.fullscreen_exit,
              '自由切换全屏',
              '顶部全屏按钮或 F11 切换沉浸与窗口；Esc 可退出应用沉浸模式。搜索页和播放器优先处理各自的返回操作。',
            ),
            const Text('键盘导航：Ctrl+M 打开菜单。确认后不再自动显示本引导，可在设置中再次查看。'),
            TextButton(
              onPressed: () => showResourceDisclaimer(context),
              child: const Text('阅读免责声明与版权说明'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: _saving ? null : _confirm,
          child: Text(_saving ? '正在保存…' : '我知道了，开始使用'),
        ),
      ],
    ),
  );

  Widget _tip(IconData icon, String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(text),
            ],
          ),
        ),
      ],
    ),
  );
}
