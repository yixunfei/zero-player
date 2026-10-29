enum FilterStrategy {
  conservative('保守自动跳过', '完整序列高置信度命中才跳过，优先避免误跳。'),
  aggressive('积极自动跳过', '允许轻微压缩、音画变化及速度差异，覆盖更多，可能增加误跳。'),
  confirm('提示后跳过', '检测命中后显示操作，由你确认跳过或忽略。');

  const FilterStrategy(this.label, this.description);
  final String label, description;

  static FilterStrategy parse(String value) =>
      values.firstWhere((v) => v.name == value, orElse: () => conservative);
}
