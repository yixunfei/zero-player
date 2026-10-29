import 'package:flutter/material.dart';
import '../features/supervision/presentation/supervision_page.dart';
import 'app_services.dart';
import 'app_theme.dart';

/// Runs before ProductApp, so its optional setup never overlaps navigation help.
final class InstallationIntroduction extends StatefulWidget {
  const InstallationIntroduction({
    super.key,
    required this.services,
    required this.child,
  });
  final AppServices services;
  final Widget child;
  @override
  State<InstallationIntroduction> createState() =>
      _InstallationIntroductionState();
}

final class _InstallationIntroductionState
    extends State<InstallationIntroduction> {
  bool _busy = false;
  String? _error;
  Future<void> _finish() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.installationAccess.finishIntroduction();
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '首次使用状态保存失败，请重试';
        });
      }
    }
  }

  Future<void> _setup(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SupervisionPage(services: widget.services),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && widget.services.supervision.configured) await _finish();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.services.installationAccess.introductionSeen) {
      return widget.child;
    }
    final settings = widget.services.settings.value;
    return MaterialApp(
      title: 'Zero Player',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        Brightness.dark,
        false,
        settings.theme,
        font: settings.font,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Builder(builder: (context) => _choices(context)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choices(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.shield_outlined, size: 40),
      const SizedBox(height: 16),
      Text('是否设置监管模式？', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      const Text(
        '监管可用独立密码保护敏感操作，并屏蔽指定频道和关键词。'
        '监管开启期间成人频道与节目过滤保持开启。你可以现在设置，也可以稍后从设置中开启。',
      ),
      const SizedBox(height: 12),
      const Text('首次使用不需要输入访问密码；仅首次尝试关闭成人过滤时需要验证。'),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy ? null : () => _setup(context),
        child: const Text('现在设置监管'),
      ),
      TextButton(
        onPressed: _busy ? null : _finish,
        child: const Text('暂不设置，开始使用'),
      ),
      if (_busy) const LinearProgressIndicator(),
    ],
  );
}
