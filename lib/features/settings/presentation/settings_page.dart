import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/platform/file_transfer.dart';
import 'home_preferences.dart';
import '../../../app/app_fonts.dart';
import '../../../app/navigation_guide.dart';
import 'disclaimer_dialog.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.settings,
    builder: (context, _) {
      final settings = services.settings.value;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('视频源与订阅'),
            subtitle: const Text('候选、手动接口、导入、健康状态'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/sources'),
          ),
          ..._appearanceOptions(context),
          _choice(
            context,
            '发现页推荐',
            'recommendation',
            settings.recommendation,
            const {
              'douban': '豆瓣',
              'bangumi': 'Bangumi',
              'hot': '影视榜单',
              'off': '关闭',
            },
          ),
          _toggle(context, '自动播放下一集', 'autoplay', settings.autoplay),
          HomePreferences(services: services),
          _toggle(
            context,
            '片段自动跳过',
            'skip',
            settings.skip,
            subtitle: '仅适用于同一来源、线路与接近的剧集时长',
          ),
          _toggle(
            context,
            '过滤显式广告分片',
            'adFilter',
            settings.adFilter,
            subtitle: '实验功能：只处理无加密静态 TS 单清单的成对 CUE 标记；不支持时保留原视频。离线文件保留完整原片。',
          ),
          _toggle(
            context,
            '成人源与内容关键词过滤',
            'filterAdult',
            settings.filterAdult,
            subtitle: '过滤成人分类来源及标题/分类中的显式成人关键词，不能识别所有漏标内容。未知分类不代表普通内容。',
          ),
          const Divider(),
          _toggle(context, '边播边缓存 HLS 分片', 'cache', settings.cache),
          ..._cacheOptions(context),
          _choice(context, '可淘汰缓存容量', 'cacheMiB', '${settings.cacheMiB}', {
            for (final value in {128, 256, 512, 1024, 2048, settings.cacheMiB})
              '$value': '$value MiB',
          }, numeric: true),
          _choice(context, '离线下载容量', 'downloadMiB', '${settings.downloadMiB}', {
            for (final value in {1024, 4096, 8192, 16384, settings.downloadMiB})
              '$value': '$value MiB',
          }, numeric: true),
          _toggle(
            context,
            '允许计费网络下载',
            'allowMetered',
            settings.allowMetered,
            subtitle: 'Android 离开前台会暂停下载，返回后可手动恢复',
          ),
          ListTile(
            title: const Text('清理可淘汰缓存'),
            subtitle: const Text('保留下载任务和正在使用的媒体'),
            trailing: const Icon(Icons.cleaning_services_outlined),
            onTap: () => perform(context, _clearCache, success: '缓存已清理'),
          ),
          const Divider(),
          ..._performanceOptions(context),
          ..._dataActions(context),
          const Divider(),
          ..._helpActions(context),
        ],
      );
    },
  );
  List<Widget> _appearanceOptions(BuildContext context) {
    final settings = services.settings.value;
    return [
      _choice(context, '主题', 'theme', settings.theme, const {
        'cinema': '影院 · 沉浸黑金（默认）',
        'dark': '深色 · 青灰',
        'light': '明亮 · 柔和暖白',
        'system': '跟随系统',
      }),
      _choice(context, '显示模式', 'mode', settings.mode, const {
        'auto': '自动 / 桌面 / 手机',
        'television': '电视大屏',
      }),
      _choice(context, '界面字体', 'font', settings.font, appFontLabels),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          '字形预览 · 发现好故事 0123456789',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      _toggle(
        context,
        '启动时沉浸全屏',
        'startFullscreen',
        settings.startFullscreen,
        subtitle: '下次启动生效；当前会话可用 Esc、F11 或顶部按钮退出全屏',
      ),
      _choice(
        context,
        '每次手动加载条目',
        'manualLoadCount',
        settings.manualLoadCount.toString(),
        {
          for (final count in {
            12,
            24,
            48,
            96,
            120,
            240,
            settings.manualLoadCount,
          })
            '$count': '$count 部（不足时显示剩余内容）',
        },
        numeric: true,
      ),
      const ListTile(
        title: Text('操作提示'),
        subtitle: Text(
          'Home / End 跳到当前列表首尾；PageUp / PageDown 翻页；Ctrl+K 搜索；Esc 取消搜索/返回；Ctrl+M 导航；F11 全屏。输入框内保留文本编辑快捷键。',
        ),
      ),
    ];
  }

  Future<void> _clearCache() async {
    await services.store.clearUnused();
    services.posters.clear();
    PaintingBinding.instance.imageCache.clear();
  }

  List<Widget> _helpActions(BuildContext context) => [
    ListTile(
      leading: const Icon(Icons.help_outline),
      title: const Text('查看导航引导'),
      subtitle: const Text('菜单、搜索和全屏操作提示'),
      onTap: () => showNavigationGuide(context, services.settings),
    ),
    ListTile(
      leading: const Icon(Icons.policy_outlined),
      title: const Text('免责声明与版权说明'),
      subtitle: const Text('项目定位、第三方资源及版权反馈渠道'),
      onTap: () => showResourceDisclaimer(context),
    ),
  ];

  List<Widget> _performanceOptions(BuildContext context) {
    final s = services.settings.value;
    return [
      _choice(context, '搜索并发数', 'searchConcurrency', '${s.searchConcurrency}', {
        for (var i = 1; i <= 16; i++) '$i': '$i 路',
      }, numeric: true),
      _toggle(
        context,
        '后台检测源可用性',
        'backgroundProbe',
        s.backgroundProbe,
        subtitle: '低优先级异步检测，保存延迟和最后检测时间；播放请求优先',
      ),
      _choice(context, '源检测并发数', 'probeConcurrency', '${s.probeConcurrency}', {
        for (var i = 1; i <= 6; i++) '$i': '$i 路',
      }, numeric: true),
      _toggle(
        context,
        '下载失败自动换源',
        'autoDownloadFallback',
        s.autoDownloadFallback,
        subtitle: '匹配同作品、年份和剧集；换源后整集重新下载',
      ),
      _toggle(
        context,
        '允许多源并发下载',
        'multiSourceDownload',
        s.multiSourceDownload,
        subtitle: '显式开启后按整集分配来源，不混拼不同源的视频分片',
      ),
      if (s.multiSourceDownload)
        _choice(
          context,
          '同时下载剧集数',
          'downloadConcurrency',
          '${s.downloadConcurrency}',
          {for (var i = 1; i <= 4; i++) '$i': '$i 集'},
          numeric: true,
        ),
      _toggle(
        context,
        '播放屏幕手势',
        'gestures',
        s.gestures,
        subtitle: '横滑快进，右侧竖滑音量，左侧竖滑画面亮度，长按倍速',
      ),
    ];
  }

  List<Widget> _cacheOptions(BuildContext context) {
    final settings = services.settings.value;
    return [
      _choice(
        context,
        '单集缓存上限',
        'episodeCacheMiB',
        '${settings.episodeCacheMiB}',
        {
          for (final value in {
            64,
            128,
            256,
            512,
            1024,
            settings.episodeCacheMiB,
          })
            '$value': '$value MiB',
        },
        numeric: true,
      ),
      _choice(
        context,
        '向前预取分片',
        'prefetchSegments',
        '${settings.prefetchSegments}',
        {for (var value = 0; value <= 10; value++) '$value': '$value 个'},
        numeric: true,
      ),
      _toggle(
        context,
        '暂停播放时继续预取',
        'cacheWhilePaused',
        settings.cacheWhilePaused,
      ),
    ];
  }

  List<Widget> _dataActions(BuildContext context) => [
    ListTile(
      title: const Text('导出本地数据备份'),
      subtitle: const Text('包含设置、源请求头、历史和直播；不含离线视频'),
      onTap: () => _backup(context),
    ),
    ListTile(
      title: const Text('从备份恢复'),
      subtitle: const Text('先校验预览，再替换本地配置；下载文件保留'),
      onTap: () => _restore(context),
    ),
    ListTile(
        title: const Text('Zero Player 0.0.1'),
      subtitle: const Text('AGPL-3.0-or-later · 本地数据 · 无需独立后端'),
      onTap: () => showLicensePage(
        context: context,
        applicationName: 'Zero Player',
          applicationVersion: '0.0.1',
        applicationLegalese: 'AGPL-3.0-or-later\n媒体依赖许可见源码 NOTICE.md',
      ),
    ),
  ];
  Widget _choice(
    BuildContext context,
    String title,
    String key,
    String value,
    Map<String, String> values, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$key/$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: [
        for (final entry in values.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (next) {
        if (next != null) {
          perform(
            context,
            () => services.settings.update({
              key: numeric ? int.parse(next) : next,
            }),
          );
        }
      },
    ),
  );
  Widget _toggle(
    BuildContext context,
    String title,
    String key,
    bool value, {
    String? subtitle,
  }) => SwitchListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: value,
    onChanged: (v) =>
        perform(context, () => services.settings.update({key: v})),
  );
  Future<void> _backup(BuildContext context) => perform(context, () async {
    if (!await confirm(
      context,
      '保存个人备份',
      '备份含源请求头与完整 URL，可能含凭据。请选择自己的存储位置，不要作为公开源分享文件。',
    )) {
      return;
    }
    await FileTransfer.saveText(
      'zero-player-backup.json',
      await services.backup.export(),
    );
  });
  Future<void> _restore(BuildContext context) => perform(context, () async {
    final text = await FileTransfer.readText();
    if (text == null) return;
    final preview = await services.backup.preview(text);
    if (!context.mounted) return;
    if (!await confirm(
      context,
      '恢复备份',
      '${preview.sourceCount} 个来源、${preview.historyCount} 条观看记录。确认替换当前设置、源和历史？损坏的数据会回滚。',
    )) {
      return;
    }
    await services.backup.restore(preview);
    await services.settings.load();
    if (context.mounted) message(context, '备份已恢复');
  });
}
