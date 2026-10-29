import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../media/content_filter/fingerprints/feature_rule.dart';
import '../../../media/content_filter/filter_types.dart';
import '../../supervision/presentation/sensitive_action.dart';
import '../../supervision/application/supervision_controller.dart';
import '../application/playback_controller.dart';
import '../domain/playback_mark_target.dart';
import 'feature_sample_preview.dart';
import '../domain/feature_time.dart';
import 'feature_time_field.dart';

Future<void> editFeatureRule(
  BuildContext context,
  PlaybackController controller, {
  FeatureRule? rule,
  bool quickCapture = false,
  SensitiveSession? authorization,
}) async {
  PlaybackMarkTarget? target;
  if (rule == null) {
    try {
      target = controller.markTarget;
    } on FormatException catch (error) {
      message(context, error.message);
      return;
    }
  }
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _FeatureRuleDialog(
      controller: controller,
      rule: rule,
      quickCapture: quickCapture,
      target: target,
      authorization: authorization,
    ),
  );
  if (saved == true) await controller.refreshFeatureRules();
}

final class _FeatureRuleDialog extends StatefulWidget {
  const _FeatureRuleDialog({
    required this.controller,
    this.rule,
    this.quickCapture = false,
    this.target,
    this.authorization,
  });
  final PlaybackController controller;
  final FeatureRule? rule;
  final bool quickCapture;
  final PlaybackMarkTarget? target;
  final SensitiveSession? authorization;
  @override
  State<_FeatureRuleDialog> createState() => _FeatureRuleDialogState();
}

final class _FeatureRuleDialogState extends State<_FeatureRuleDialog> {
  final _name = TextEditingController();
  final _start = TextEditingController(), _end = TextEditingController();
  final _before = TextEditingController(text: '0'),
      _after = TextEditingController(text: '0');
  CancellationToken _token = CancellationToken();
  FeatureMode _mode = FeatureMode.audio;
  FeatureScope _scope = FeatureScope.channel;
  PlaybackMarkTarget? _target;
  bool _reextract = false;
  bool get _canExtract => widget.rule == null || _reextract;
  FeatureRule? _preview;
  bool _working = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _target = widget.target;
    _scope = rule?.scope ?? FeatureScope.channel;
    final current = widget.controller.originalPosition.inMilliseconds;
    final from =
        rule?.originStartMs ??
        (widget.controller.featureStart?.inMilliseconds ??
            (current - (widget.quickCapture ? 4000 : 2000)).clamp(0, current));
    final to = rule == null ? current : from + rule.sampleMs;
    _start.text = featureTimeText(from);
    _end.text = featureTimeText(to);
    _name.text = rule?.label ?? '不良信息样本';
    _before.text = ((rule?.beforeMs ?? 0) / 1000).toString();
    _after.text = ((rule?.afterMs ?? 0) / 1000).toString();
    _mode = rule?.mode ?? FeatureMode.audio;
    _preview = rule;
    if (widget.quickCapture && to - from >= 1000) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _capture();
      });
    }
  }

  @override
  void dispose() {
    _token.cancel();
    for (final field in [_name, _start, _end, _before, _after]) {
      field.dispose();
    }
    super.dispose();
  }

  int _ms(TextEditingController field) {
    if (field == _start || field == _end) return parseFeatureTime(field.text);
    final value = double.tryParse(field.text);
    if (value == null || !value.isFinite || value < 0) {
      throw const FormatException('请输入有效的非负秒数');
    }
    return (value * 1000).round();
  }

  Future<void> _capture() async {
    if (_working || _saving) return;
    _token = CancellationToken();
    setState(() {
      _working = true;
      _preview = null;
      _error = null;
    });
    try {
      widget.controller.checkMarkTarget(_target!);
      final rule = await widget.controller.captureFeature(
        from: Duration(milliseconds: _ms(_start)),
        to: Duration(milliseconds: _ms(_end)),
        label: _name.text,
        mode: _mode,
        beforeMs: _ms(_before),
        afterMs: _ms(_after),
        token: _token,
      );
      if (mounted && !_saving) {
        setState(() {
          _preview = widget.rule == null
              ? rule
              : rule.copyWith(
                  id: widget.rule!.id,
                  enabled: widget.rule!.enabled,
                );
          _start.text = featureTimeText(rule.originStartMs);
          _end.text = featureTimeText(rule.originStartMs + rule.sampleMs);
        });
      }
    } catch (error) {
      if (mounted && !_saving && !_token.isCancelled) {
        setState(() => _error = _errorText(error));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _errorText(Object error) => switch (error) {
    FormatException e => e.message,
    FilterFailure e => e.message,
    _ => '采集暂不可用。可重试、改用画面，或仅保存本集区间。',
  };

  Future<void> _captureVisual() async {
    setState(() => _mode = FeatureMode.visual);
    await _capture();
  }

  void _beginRecapture() {
    try {
      final target = widget.controller.markTarget;
      if (!widget.rule!.appliesTo(
        source: target.sourceId,
        series: widget.controller.featureSeriesKey,
      )) {
        throw const FormatException('请在此特征所属频道或同一作品中重新提取');
      }
      final current = widget.controller.originalPosition.inMilliseconds;
      setState(() {
        _target = target;
        _reextract = true;
        _preview = null;
        _error = null;
        _start.text = featureTimeText((current - 4000).clamp(0, current));
        _end.text = featureTimeText(current);
      });
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _saveInterval() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    _token.cancel();
    try {
      final before = _ms(_before), after = _ms(_after);
      if (before > 30000 || after > 120000) {
        throw const FormatException('向前最多 30 秒，向后最多 120 秒');
      }
      final start = _ms(_start), end = _ms(_end);
      if (end <= start || end > widget.target!.duration.inMilliseconds) {
        throw const FormatException('请填写有效起止时间，终点不能超过总时长');
      }
      await widget.controller.saveEpisodeMark(
        target: widget.target!,
        start: Duration(milliseconds: (start - before).clamp(0, start)),
        end: Duration(
          milliseconds: (end + after).clamp(
            0,
            widget.target!.duration.inMilliseconds,
          ),
        ),
        label: _name.text,
      );
      if (mounted) Navigator.pop(context, false);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_working || _saving) return;
    setState(() => _saving = true);
    try {
      await _saveOnce();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOnce() => perform(context, () async {
    final preview = _preview;
    if (preview == null) return;
    if (_target != null) {
      widget.controller.checkMarkTarget(_target!);
    }
    if (_scope == FeatureScope.series && preview.seriesKey.isEmpty) {
      throw const FormatException('此样本缺少作品身份，请重新提取后再设为全剧范围');
    }
    final rule = FeatureRule.fromJson({
      ...preview.toJson(),
      'label': _name.text.trim(),
      'mode': _mode.name,
      'scope': _scope.name,
      'seriesKey': preview.seriesKey,
      'beforeMs': _ms(_before),
      'afterMs': _ms(_after),
    });
    final services = widget.controller.services;
    Future<void> save() async {
      if (_target != null) widget.controller.checkMarkTarget(_target!);
      await services.filterFeatures.save(rule);
      if (!services.settings.value.contentFilter) {
        await services.settings.update({'contentFilter': true});
      }
    }

    final session = widget.authorization;
    final bool saved;
    if (session != null) {
      await session.run(save);
      saved = true;
    } else {
      saved = await runSensitive(
        context,
        services.supervision,
        SensitiveOperation.contentFilter,
        save,
        needed: widget.rule != null,
      );
    }
    if (mounted && saved) Navigator.pop(context, true);
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.rule == null ? '保存可复用内容特征' : '编辑过滤特征'),
    content: SizedBox(width: 540, child: _content()),
    actions: [
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: _actions(),
      ),
    ],
  );

  Widget _content() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('选择完整不良片段（1 秒至 10 分钟），内部自动提取多个短特征。按内容与相对位置跨集匹配，无需安装增强资源。'),
      const SizedBox(height: 12),
      TextField(
        controller: _name,
        maxLength: 120,
        enabled: !_working && !_saving,
        decoration: const InputDecoration(labelText: '特征名称'),
      ),
      _timeFields(
        _clockField(_start, '片段起点（分:秒／时:分:秒）'),
        _clockField(_end, '片段终点（分:秒／时:分:秒）'),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<FeatureScope>(
        initialValue: _scope,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '生效范围'),
        items: const [
          DropdownMenuItem(
            value: FeatureScope.channel,
            child: Text('本频道 · 所有影片与集数'),
          ),
          DropdownMenuItem(
            value: FeatureScope.series,
            child: Text('全剧 · 同一作品所有集数'),
          ),
        ],
        onChanged: _working || _saving
            ? null
            : (value) => setState(() => _scope = value!),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<FeatureMode>(
        key: ValueKey(_mode),
        isExpanded: true,
        initialValue: _mode,
        decoration: const InputDecoration(labelText: '匹配方式'),
        items: [
          for (final mode in FeatureMode.values)
            DropdownMenuItem(
              value: mode,
              child: Text(
                featureModeLabel(mode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _working || _saving || !_canExtract
            ? null
            : (value) => setState(() {
                _mode = value!;
                _preview = null;
              }),
      ),
      const SizedBox(height: 12),
      _timeFields(
        _timeField(_before, '向前跳过（0–30 秒）'),
        _timeField(_after, '向后跳过（0–120 秒）'),
      ),
      ..._previewWidgets(),
    ],
  );

  List<Widget> _previewWidgets() => [
    const SizedBox(height: 12),
    Text(_rangePreview()),
    const Text('仅保存本集区间只按固定时间跳过，不会跨集复用。内容特征需要采集成功后保存。'),
    if (_preview != null) ...[
      const SizedBox(height: 12),
      FeatureSamplePreview(rule: _preview!),
      Text(
        '已提取 ${_preview!.signatures.fold(0, (n, a) => n + a.visual.length)} 个画面和 ${_preview!.signatures.fold(0, (n, a) => n + a.audio.length)} 个音频特征。',
      ),
      if (_preview!.captureNote.isNotEmpty) Text(_preview!.captureNote),
      const Text('匹配依据是连续样本，静音、纯色或无辨识度样本不会用于自动判定。更换配音、明显裁剪或内容重做时请重新提取。'),
    ],
    if (_working)
      const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      ),
    if (_error != null)
      Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    if (_error != null && _mode != FeatureMode.visual && _canExtract)
      OutlinedButton.icon(
        onPressed: _working || _saving ? null : _captureVisual,
        icon: const Icon(Icons.image_outlined),
        label: const Text('改用画面并采集'),
      ),
  ];

  List<Widget> _actions() => [
    TextButton(
      onPressed: _saving ? null : () => Navigator.pop(context),
      child: Text(_working ? '取消采集' : '取消'),
    ),
    if (widget.rule == null)
      FilledButton.tonal(
        onPressed: _saving ? null : _saveInterval,
        child: const Text('仅保存本集区间'),
      ),
    if (widget.rule != null && !_reextract)
      OutlinedButton(
        onPressed: _working || _saving ? null : _beginRecapture,
        child: const Text('从当前视频重新提取'),
      ),
    if (_canExtract)
      OutlinedButton(
        onPressed: _working || _saving ? null : _capture,
        child: const Text('采集并预览'),
      ),
    FilledButton(
      onPressed: _working || _saving || _preview == null ? null : _save,
      child: const Text('保存并应用'),
    ),
  ];

  Widget _timeFields(Widget first, Widget second) {
    final compact =
        MediaQuery.sizeOf(context).width < 450 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [first, const SizedBox(height: 12), second],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }

  Widget _timeField(
    TextEditingController controller,
    String label, {
    bool sample = false,
  }) => TextField(
    controller: controller,
    enabled: !_working && !_saving && (!sample || _canExtract),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {
      if (sample) _preview = null;
    }),
  );

  Widget _clockField(TextEditingController controller, String label) =>
      FeatureTimeField(
        controller: controller,
        label: label,
        enabled: !_working && !_saving && _canExtract,
        currentTime: () => widget.controller.originalPosition.inMilliseconds,
        onChanged: () => setState(() => _preview = null),
      );

  String _rangePreview() {
    try {
      final from = (_ms(_start) - _ms(_before)).clamp(0, 86400000);
      final end = _ms(_end) + _ms(_after);
      final to = (_target == null
          ? end
          : end.clamp(0, _target!.duration.inMilliseconds));
      return '本集跳过范围：${featureTimeText(from)}–${featureTimeText(to)}（${from / 1000}–${to / 1000} 秒）。其他位置按匹配偏移定位完整片段；默认不额外延长边界。';
    } on FormatException {
      return '请填写样本范围和前后偏移。';
    }
  }
}

String featureModeLabel(FeatureMode mode) => switch (mode) {
  FeatureMode.visual => '画面相似',
  FeatureMode.audio => '音频相似',
  FeatureMode.both => '画面与音频同时相似',
};
