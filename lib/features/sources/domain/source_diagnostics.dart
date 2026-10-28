import 'dart:convert';

final class SourceDiagnostics {
  const SourceDiagnostics({
    required this.state,
    required this.checkedAt,
    this.addresses = const [],
    this.dnsMs,
    this.tcpMs,
    this.port,
    this.message = '',
    this.requests = const [],
    this.dnsEvidence = const [],
  });
  final String state;
  final DateTime checkedAt;
  final List<String> addresses;
  final int? dnsMs, tcpMs, port;
  final String message;
  final List<Map<String, Object?>> requests;
  final List<String> dnsEvidence;
  bool get possiblyInvalid =>
      {'unavailable', 'inconclusive', 'missingDomain'}.contains(state);
  String get label => switch (state) {
    'available' => '接口可用',
    'unavailable' => '可能失效 · 检测失败',
    'missingDomain' => '域名不存在 · 已停用待复检',
    _ => '可能失效 · 未确定',
  };

  Map<String, Object?> toJson() => {
    'state': state,
    'checkedAt': checkedAt.millisecondsSinceEpoch,
    'addresses': addresses,
    'dnsMs': dnsMs,
    'tcpMs': tcpMs,
    'port': port,
    'message': message,
    'requests': requests,
    'dnsEvidence': dnsEvidence,
  };

  static SourceDiagnostics? decode(String? text) {
    if (text == null) return null;
    try {
      final map = jsonDecode(text) as Map;
      return SourceDiagnostics(
        state: map['state'] as String,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(map['checkedAt'] as int),
        addresses: (map['addresses'] as List).cast<String>(),
        dnsMs: map['dnsMs'] as int?,
        tcpMs: map['tcpMs'] as int?,
        port: map['port'] as int?,
        message: map['message'] as String? ?? '',
        requests: (map['requests'] as List)
            .map((r) => Map<String, Object?>.from(r as Map))
            .toList(),
        dnsEvidence: (map['dnsEvidence'] as List? ?? []).cast<String>(),
      );
    } catch (_) {
      return null;
    }
  }
}
