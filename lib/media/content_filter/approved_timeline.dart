/// Each published slice has an explicit original and output position.
/// Rejected slices never enter the playback manifest.
final class ApprovedSlice {
  const ApprovedSlice({
    required this.sequence,
    required this.originalStart,
    required this.outputStart,
    required this.duration,
    required this.path,
  });
  final int sequence;
  final Duration originalStart;
  final Duration outputStart;
  final Duration duration;
  final String path;
  Duration get outputEnd => outputStart + duration;
}

final class ApprovedTimeline {
  final _slices = <ApprovedSlice>[];
  List<ApprovedSlice> get slices => List.unmodifiable(_slices);
  Duration get duration =>
      _slices.isEmpty ? Duration.zero : _slices.last.outputEnd;

  ApprovedSlice add(Duration original, Duration length, String path) {
    if (length <= Duration.zero || original < Duration.zero) {
      throw ArgumentError('Invalid approved interval');
    }
    if (_slices.isNotEmpty &&
        original < _slices.last.originalStart + _slices.last.duration) {
      throw ArgumentError('Approved intervals must not overlap');
    }
    final slice = ApprovedSlice(
      sequence: _slices.length,
      originalStart: original,
      outputStart: duration,
      duration: length,
      path: path,
    );
    _slices.add(slice);
    return slice;
  }

  Duration originalPosition(Duration output) {
    if (_slices.isEmpty) return Duration.zero;
    for (final slice in _slices) {
      if (output < slice.outputEnd) {
        final offset = output - slice.outputStart;
        return slice.originalStart +
            (offset < Duration.zero ? Duration.zero : offset);
      }
    }
    return _slices.last.originalStart + _slices.last.duration;
  }
}
