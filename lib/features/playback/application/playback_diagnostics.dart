/// Bounded in-memory events. No raw URLs, credentials, or media are recorded.
final class PlaybackDiagnostics {
  final _events = <String>[];
  void add(String message) {
    if (_events.isNotEmpty && _events.last.endsWith(' $message')) return;
    _events.add('${DateTime.now().toIso8601String()} $message');
    if (_events.length > 60) _events.removeAt(0);
  }

  String report(Map<String, Object?> fields) => [
    for (final entry in fields.entries) '${entry.key}: ${entry.value}',
    '',
    '最近事件:',
    ..._events,
  ].join('\n');
}
