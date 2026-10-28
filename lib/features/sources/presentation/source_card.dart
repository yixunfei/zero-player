import '../../supervision/presentation/sensitive_action.dart';
import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../data/source_repository.dart';
import '../domain/video_source.dart';
import 'source_favorite_button.dart';

final class SourceCard extends StatelessWidget {
  const SourceCard({
    super.key,
    required this.source,
    required this.repository,
    required this.selected,
    required this.onSelected,
    required this.onDetails,
    required this.onAction,
  });
  final VideoSource source;
  final SourceRepository repository;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onDetails;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => repository.policy == null
      ? _card(context)
      : ListenableBuilder(
          listenable: repository.policy!,
          builder: (context, _) => _card(context),
        );

  bool get _restricted => !(repository.policy?.sourceAllowed(source) ?? true);

  Widget _card(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) => onSelected(value ?? false),
              ),
              Expanded(
                child: InkWell(
                  onTap: onDetails,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _restricted ? '受限频道' : source.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          _restricted
                              ? '频道和网站信息已被过滤或监管规则隐藏'
                              : source.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SourceFavoriteButton(source: source, repository: repository),
              PopupMenuButton<String>(
                onSelected: onAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'details', child: Text('渠道详情')),
                  PopupMenuItem(value: 'edit', child: Text('编辑渠道')),
                  PopupMenuItem(value: 'probe', child: Text('探测接口')),
                  PopupMenuItem(value: 'reset', child: Text('解除退避')),
                  PopupMenuItem(value: 'delete', child: Text('移除')),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statusTags(context),
                Text(
                  _restricted
                      ? '禁止访问受限内容'
                      : source.error ??
                            source.diagnostics?.label ??
                            (source.apiOk ? '接口查询成功，媒体未验证' : '尚未验证接口和播放'),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: onDetails,
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: const Text('详情'),
                    ),
                    const Spacer(),
                    Text(source.enabled ? '已启用' : '已停用'),
                    Switch(
                      value: source.enabled,
                      onChanged: (value) => perform(
                        context,
                        () => runSensitive(
                          context,
                          repository.policy?.supervision,
                          SensitiveOperation.channels,
                          () => repository.setEnabled(source.id, value),
                          needed: value,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _statusTags(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        source.classification == 'adult'
            ? '成人'
            : source.classification == 'general'
            ? '普通'
            : '未分类',
      ),
      if (source.possiblyInvalid)
        Chip(
          label: const Text('可能失效'),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      if (source.suppressed) const Text('已移除'),
      if (source.endpoint.scheme == 'http') const Text('HTTP 明文'),
      Text(
        source.diagnostics?.tcpMs == null
            ? 'TCP Ping 未测'
            : 'TCP Ping ${source.diagnostics!.tcpMs} ms',
      ),
    ],
  );
}
