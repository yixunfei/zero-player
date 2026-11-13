part of 'book_reader_page.dart';

extension _ReaderSession on _BookReaderPageState {
  void _startAutomation() {
    _autoTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_ready || _controls || ModalRoute.of(context)?.isCurrent != true) {
        _autoElapsed = 0;
        return;
      }
      if (_style.mode == ReaderTurnMode.scroll) {
        if (_viewport.currentState?.autoScroll(_style.scrollSpeed * .05) ==
            true) {
          return;
        }
        if (_canCross(1)) {
          _cross(1);
        } else {
          _stopAutomation();
        }
      } else {
        _autoElapsed += .05;
        if (_autoElapsed < _style.autoSeconds) return;
        _autoElapsed = 0;
        if (_progress.value.page >= _progress.value.pages && !_canCross(1)) {
          _stopAutomation();
        } else {
          _viewport.currentState?.turn(1);
        }
      }
    });
  }

  void _stopAutomation() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoElapsed = 0;
    if (_autoRunning && mounted) _changeAutomation(false);
  }

  void _toggleAutomation() {
    if (!_style.autoEnabled || !_ready || _autoRunning) return;
    _changeAutomation(true);
    _autoElapsed = 0;
    _startAutomation();
    _paperFocus.requestFocus();
  }
}
