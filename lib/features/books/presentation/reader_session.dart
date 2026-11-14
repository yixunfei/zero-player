part of 'book_reader_page.dart';

extension _ReaderSession on _BookReaderPageState {
  void _advanceAutomatically(double? seconds) {
    if (!_ready ||
        _controls ||
        (!_configuring && ModalRoute.of(context)?.isCurrent != true)) {
      return;
    }
    final viewport = _viewport.currentState;
    if (viewport == null) return;
    if (seconds != null) {
      if (viewport.autoScroll(_style.scrollSpeed * seconds)) return;
      if (_canCross(1)) {
        _cross(1);
      } else {
        _stopAutomation();
      }
      return;
    }
    if (_progress.value.page >= _progress.value.pages && !_canCross(1)) {
      _stopAutomation();
    } else {
      viewport.turn(1);
    }
  }

  void _startAutomation() {
    if (!_ready || !_style.autoEnabled) return;
    _changeAutomation(true);
    _automation.start(
      scroll: _style.mode == ReaderTurnMode.scroll,
      interval: _style.autoSeconds,
    );
  }

  void _stopAutomation() {
    _automation.stop();
    if (_autoRunning && mounted) _changeAutomation(false);
  }
}
