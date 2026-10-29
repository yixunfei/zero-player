import '../../../media/content_filter/filter_types.dart';
import '../../../media/hls/timeline.dart';

/// Keeps weak keyword proposals separate from user-approved content boundaries.
final class FilterDetectionQueue {
  final _pending = <FilterDetection>[];
  final _handled = <FilterDetection>[];
  int get length => _pending.length;

  bool _overlaps(RemovedInterval a, RemovedInterval b) =>
      a.start < b.end && a.end > b.start;

  bool _covers(RemovedInterval a, RemovedInterval b) =>
      a.start <= b.start && a.end >= b.end;

  void add(FilterDetection hit) {
    if (_handled.any(
      (old) => hit.requiresConfirmation
          ? _overlaps(old.range, hit.range)
          : !old.requiresConfirmation && _covers(old.range, hit.range),
    )) {
      return;
    }
    if (hit.requiresConfirmation) {
      if (_pending.any((old) => _overlaps(old.range, hit.range))) return;
    } else {
      _pending.removeWhere(
        (old) => old.requiresConfirmation && _overlaps(old.range, hit.range),
      );
      if (_pending.any(
        (old) => !old.requiresConfirmation && _covers(old.range, hit.range),
      )) {
        return;
      }
    }
    _pending.add(hit);
  }

  FilterDetection? at(Duration position) {
    _pending.removeWhere((hit) => hit.range.end <= position);
    final active = _pending.where(
      (hit) => position >= hit.range.start && position < hit.range.end,
    );
    return active.where((hit) => !hit.requiresConfirmation).firstOrNull ??
        active.firstOrNull;
  }

  void handle(FilterDetection hit) {
    _pending.removeWhere(
      (other) =>
          identical(other, hit) ||
          (!hit.requiresConfirmation &&
              (other.requiresConfirmation
                  ? _overlaps(other.range, hit.range)
                  : _covers(hit.range, other.range))),
    );
    _handled.add(hit);
  }

  void retry(FilterDetection hit) {
    _handled.remove(hit);
    add(hit);
  }

  void clear() {
    _pending.clear();
    _handled.clear();
  }
}
