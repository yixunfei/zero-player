import 'dart:convert';

enum LiveAvailability { unknown, responding, unavailable, inconclusive }

final class LiveHealth {
  const LiveHealth({
    this.enabled = true,
    this.availability = LiveAvailability.unknown,
    this.checkedAt,
    this.latencyMs,
    this.message = '',
    this.preferredUrl,
  });
  final bool enabled;
  final LiveAvailability availability;
  final DateTime? checkedAt;
  final int? latencyMs;
  final String message;
  final String? preferredUrl;
  String get label => !enabled
      ? '已停用'
      : switch (availability) {
          LiveAvailability.unknown => '未检测',
          LiveAvailability.responding => '有媒体响应 · $latencyMs ms',
          LiveAvailability.unavailable => '检测不可用',
          LiveAvailability.inconclusive => '检测未确定，可尝试播放',
        };
  factory LiveHealth.decode(Object? value, List<Uri> urls) {
    try {
      final data = jsonDecode(value as String) as Map;
      final valid = data['signature'] == urls.join('|');
      return LiveHealth(
        enabled: data['enabled'] != false,
        availability: valid
            ? LiveAvailability.values.firstWhere(
                (v) => v.name == data['availability'],
                orElse: () => LiveAvailability.unknown,
              )
            : LiveAvailability.unknown,
        checkedAt: valid && data['checkedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(data['checkedAt'] as int)
            : null,
        latencyMs: valid ? data['latencyMs'] as int? : null,
        message: valid ? data['message'] as String? ?? '' : '',
        preferredUrl: valid ? data['preferredUrl'] as String? : null,
      );
    } catch (_) {
      return const LiveHealth();
    }
  }
}
