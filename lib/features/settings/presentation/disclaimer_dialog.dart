import 'package:flutter/material.dart';

const resourceDisclaimer = [
  (
    '项目定位',
    'Zero Player 仅提供公开网络信息的聚合、检索及播放器入口，用于学习与技术交流。项目本身不制作、上传、存储或运营第三方影视内容；用户主动启用的本地缓存与下载由用户自行管理。',
  ),
  (
    '资源与版权',
    '聚合展示的节目资料、封面、播放链接及媒体内容均来自公开网络的第三方渠道。相关版权及其他权利归原权利人所有。公开可访问不代表已获授权，本项目不授予任何第三方内容的使用许可。',
  ),
  (
    '使用责任',
    '请遵守所在地适用的法律法规及资源提供方的使用条款，仅在取得相应授权或法律允许的范围内访问、缓存或下载内容，不得用于侵权传播或未经许可的商业用途。',
  ),
  (
    '第三方渠道与版权反馈',
    '第三方渠道独立提供并管理相关内容，其可用性、准确性、合法性与安全性不由本项目保证。如发现版权问题，请通过对应渠道提供商或原始发布平台的公开投诉、联系渠道处理，并停止使用相关资源；可在“视频源与订阅”中停用或移除该来源。',
  ),
  ('声明范围', '本说明用于明确项目功能及资源来源，不构成对第三方内容合法性的承诺，也不排除适用法律规定不得排除的责任。'),
];

Future<void> showResourceDisclaimer(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('免责声明与版权说明'),
    scrollable: true,
    content: SizedBox(
      width: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final section in resourceDisclaimer) ...[
            Text(section.$1, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(section.$2),
            const SizedBox(height: 18),
          ],
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭说明'),
      ),
    ],
  ),
);
