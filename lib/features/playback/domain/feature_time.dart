/// Accepts timeline clocks or exact seconds. Never silently accepts 01:90.
int parseFeatureTime(String text) {
  final value = text.trim();
  if (!RegExp(
    r'^[0-9]+(?::[0-9]{1,2}){0,2}(?:[.][0-9]{1,3})?$',
  ).hasMatch(value)) {
    throw const FormatException('请输入分:秒、时:分:秒或精确秒数，最多三位小数');
  }
  final parts = value.split(':').map(double.parse).toList();
  if (parts.length > 1 && parts.skip(1).any((v) => v >= 60)) {
    throw const FormatException('时间中的分、秒必须小于 60');
  }
  var seconds = 0.0;
  for (final part in parts) {
    seconds = seconds * 60 + part;
  }
  if (!seconds.isFinite || seconds > 86400) {
    throw const FormatException('时间不能超过 24 小时');
  }
  return (seconds * 1000).round();
}

String featureTimeText(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  final minute = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final second = (seconds % 60).toString().padLeft(2, '0');
  final clock = seconds >= 3600
      ? '${seconds ~/ 3600}:$minute:$second'
      : '$minute:$second';
  final fraction = milliseconds % 1000;
  return fraction == 0
      ? clock
      : '$clock.${fraction.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
}
