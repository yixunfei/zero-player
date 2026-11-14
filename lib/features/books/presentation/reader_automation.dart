import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Page turns use a timer. Scrolling uses elapsed frame time and pixel speed.
final class ReaderAutomation {
  ReaderAutomation(this._vsync, this.advance);

  final TickerProvider _vsync;
  final void Function(double? seconds) advance;
  Ticker? _ticker;
  Timer? _timer;
  Duration _previous = Duration.zero;

  void start({required bool scroll, required double interval}) {
    stop();
    if (scroll) {
      (_ticker ??= _vsync.createTicker(_frame)).start();
    } else {
      _timer = Timer.periodic(
        Duration(milliseconds: (interval * 1000).round()),
        (_) => advance(null),
      );
    }
  }

  void _frame(Duration elapsed) {
    final seconds = (elapsed - _previous).inMicroseconds / 1000000;
    _previous = elapsed;
    if (seconds > 0) advance(seconds.clamp(0.0, .1));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _ticker?.stop();
    _previous = Duration.zero;
  }

  void dispose() {
    stop();
    _ticker?.dispose();
  }
}
