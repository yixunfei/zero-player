import 'dart:async';
import '../../settings/application/settings_controller.dart';
import 'source_probe.dart';

/// Background means asynchronous application work, not an Android OS service.
final class BackgroundSourceMonitor {
  BackgroundSourceMonitor(this.probe, this.settings);
  final SourceProbe probe;
  final SettingsController settings;
  Timer? _timer;
  Future<void>? _pending;
  bool _closed = false;
  bool _started = false;

  void start() {
    if (_started || _closed) return;
    _started = true;
    settings.addListener(_settingsChanged);
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => check());
    check();
  }

  void _settingsChanged() {
    if (!settings.value.backgroundProbe) {
      probe.cancel();
    } else {
      check();
    }
  }

  void check() {
    if (_closed || !settings.value.backgroundProbe || _pending != null) return;
    _pending = _run()
        .catchError((Object _) {})
        .whenComplete(() => _pending = null);
  }

  Future<void> _run() async {
    final now = DateTime.now();
    final all = await probe.repository.all();
    if (_closed || !settings.value.backgroundProbe) return;
    final due = all
        .where(
          (s) =>
              s.enabled &&
              (s.retryAfter == null || s.retryAfter!.isBefore(now)) &&
              (s.checkedAt == null ||
                  now.difference(s.checkedAt!) > const Duration(hours: 6)),
        )
        .toList();
    await probe.run(due, concurrency: settings.value.probeConcurrency);
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    if (_started) settings.removeListener(_settingsChanged);
    probe.cancel();
    await _pending;
    probe.dispose();
  }
}
