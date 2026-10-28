import 'dart:convert';

enum LiveAvailability { unknown, responding, unavailable, inconclusive }

final class LiveHealth {
  const LiveHealth({
    this.enabled = true,
    this.removed = false,
    this.availability = LiveAvailability.unknown,
    this.checkedAt,
    this.latencyMs,
    this.message = '',
    this.preferredUrl,
    this.resolution,
    this.languages = const [],
  });
  final bool enabled;
  final bool removed;
  final LiveAvailability availability;
  final DateTime? checkedAt;
  final int? latencyMs;
  final String message;
  final String? preferredUrl;
  final String? resolution;
  final List<String> languages;
  String get availabilityLabel => switch (availability) {
    LiveAvailability.unknown => '未检测',
    LiveAvailability.responding =>
      '有媒体响应${latencyMs == null ? '' : ' · $latencyMs ms'}',
    LiveAvailability.unavailable => '检测不可用',
    LiveAvailability.inconclusive => '检测未确定',
  };
  String get label => removed
      ? '已移除'
      : !enabled
      ? '已停用'
      : availabilityLabel;
  factory LiveHealth.decode(Object? value, List<Uri> urls) {
    try {
      final data = jsonDecode(value as String) as Map;
      final valid = data['signature'] == urls.join('|');
      return LiveHealth(
        enabled: data['enabled'] != false,
        removed: data['removed'] == true,
        availability: valid
            ? LiveAvailability.values.firstWhere(
                (v) => v.name == data['availability'],
                orElse: () => LiveAvailability.unknown,
              )
            : LiveAvailability.unknown,
        checkedAt: valid && data['checkedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(data['checkedAt'] as int)
            : null,
        latencyMs: valid && data['latencyMs'] is int
            ? data['latencyMs'] as int
            : null,
        message: valid && data['message'] is String
            ? data['message'] as String
            : '',
        preferredUrl: valid && data['preferredUrl'] is String
            ? data['preferredUrl'] as String
            : null,
        resolution: valid && data['resolution'] is String
            ? data['resolution'] as String
            : null,
        languages: valid && data['languages'] is List
            ? (data['languages'] as List).whereType<String>().toList()
            : const [],
      );
    } catch (_) {
      return const LiveHealth();
    }
  }
}
