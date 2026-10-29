import 'dart:async';
import 'dart:io';

import '../../core/network/cancellation_token.dart';
import 'approved_timeline.dart';
import 'filter_types.dart';
import '../hls/timeline.dart';

enum FilterPhase {
  preparing,
  inspecting,
  ready,
  waiting,
  completed,
  failed,
  closed,
}

final class FilterStatus {
  const FilterStatus(this.phase, this.message, {this.skipped = Duration.zero});
  final FilterPhase phase;
  final String message;
  final Duration skipped;
}

/// Only this producer may publish media. A timeout/error never becomes allow.
final class FilterSession {
  FilterSession({
    required this.input,
    required this.directory,
    required this.sampler,
    required this.inspector,
    this.start = Duration.zero,
    this.window = const Duration(seconds: 24),
    this.sliceDuration = const Duration(seconds: 4),
    this.startupBuffer = const Duration(seconds: 12),
    this.declaredAds,
  });
  final Uri input;
  final Directory directory;
  final SliceSampler sampler;
  final SliceInspector inspector;
  final Duration start;
  final Duration window;
  final Duration sliceDuration;
  final Duration startupBuffer;
  final List<RemovedInterval> Function()? declaredAds;
  final cancellation = CancellationToken();
  final timeline = ApprovedTimeline();
  final _changes = StreamController<FilterStatus>.broadcast();
  final _ready = Completer<void>();
  Completer<void>? _wake;
  Future<void>? _running;
  Future<void>? _closing;
  Duration sourceDuration = Duration.zero;
  Duration _outputPosition = Duration.zero;
  Duration _skipped = Duration.zero;
  int _prunedThrough = 0;
  final _held = <MediaSlice>[];
  final _blocked = <RemovedInterval>[];
  Duration _publishedThrough = Duration.zero;
  Duration get _retention => inspector is DeferredSliceInspector
      ? (inspector as DeferredSliceInspector).retention
      : Duration.zero;
  bool finished = false;
  String? failure;
  FilterStatus status = const FilterStatus(FilterPhase.preparing, '正在准备离线检测');
  Stream<FilterStatus> get changes => _changes.stream;
  bool get closed => _closing != null;

  Future<void> begin() {
    if (closed) return Future.error(const FilterFailure('检测会话已关闭'));
    _running ??= _produce();
    return _ready.future;
  }

  void observe(Duration outputPosition) {
    _outputPosition = outputPosition;
    if (_wake?.isCompleted == false) _wake!.complete();
  }

  void _report(FilterPhase phase, String message) {
    if (closed) return;
    status = FilterStatus(phase, message, skipped: _skipped);
    _changes.add(status);
  }

  Future<void> _produce() async {
    try {
      _validateConfiguration();
      await directory.create(recursive: true);
      await inspector.prepare(cancellation);
      sourceDuration = await sampler.duration(input, cancellation);
      if (sourceDuration <= Duration.zero || start >= sourceDuration) {
        throw const FilterFailure('无法确认点播时长，严格过滤已停止播放');
      }
      await _scan();
      await _flush(sourceDuration);
      cancellation.check();
      finished = true;
      if (timeline.slices.isEmpty) {
        throw const FilterFailure('没有可放行的片段，已停止播放');
      }
      _report(FilterPhase.completed, '检测完成');
      if (!_ready.isCompleted) _ready.complete();
    } catch (error) {
      if (!closed) {
        failure = error is FilterFailure ? error.message : '检测失败，已停止放行；请重试';
        _report(FilterPhase.failed, failure!);
      }
      if (!_ready.isCompleted) {
        _ready.completeError(FilterFailure(failure ?? '检测已取消'));
      }
    }
  }

  Future<void> _scan() async {
    for (var cursor = start; cursor < sourceDuration;) {
      cancellation.check();
      await _waitForRoom();
      final ranges = [..._declaredRanges(), ..._blocked];
      final skip = ranges
          .where((r) => cursor >= r.start && cursor < r.end)
          .firstOrNull;
      if (skip != null) {
        _skipped += skip.end - cursor;
        cursor = skip.end;
        await _flush(cursor - _retention);
        _report(FilterPhase.inspecting, '已跳过明确标记的过滤区间');
        continue;
      }
      var length = sourceDuration - cursor;
      if (length > sliceDuration) length = sliceDuration;
      for (final range in ranges) {
        if (range.start > cursor && range.start < cursor + length) {
          length = range.start - cursor;
        }
      }
      await _inspect(cursor, length);
      cursor += length;
      await _flush(cursor - _retention);
    }
  }

  Future<void> _waitForRoom() async {
    while (timeline.duration - _outputPosition >= window) {
      cancellation.check();
      _wake = Completer<void>();
      await _wake!.future;
    }
    cancellation.check();
  }

  void _validateConfiguration() {
    if (start < Duration.zero ||
        sliceDuration <= Duration.zero ||
        window < sliceDuration ||
        startupBuffer <= Duration.zero ||
        startupBuffer > window) {
      throw const FilterFailure('检测缓冲配置无效，已停止放行');
    }
  }

  List<RemovedInterval> _declaredRanges() {
    final ranges = declaredAds?.call() ?? const <RemovedInterval>[];
    var previous = Duration.zero;
    for (final range in ranges) {
      if (range.start < previous ||
          range.end <= range.start ||
          range.end > sourceDuration) {
        throw const FilterFailure('广告标记范围无效，已停止放行');
      }
      previous = range.end;
    }
    return ranges;
  }

  Future<void> _inspect(Duration start, Duration length) async {
    _report(FilterPhase.inspecting, '正在超前检查画面与口播');
    final work = Directory('${directory.path}/slice_${start.inMicroseconds}');
    final slice = await sampler.sample(
      input,
      start,
      length,
      work,
      cancellation,
    );
    cancellation.check();
    final decision = await inspector.inspect(slice, cancellation);
    cancellation.check();
    if (decision.verdict == FilterVerdict.uncertain) {
      throw FilterFailure(decision.reason);
    }
    _held.add(slice);
    if (decision.verdict == FilterVerdict.block) {
      final ranges = decision.ranges.isEmpty && !decision.requiresConfirmation
          ? [RemovedInterval(start, start + length)]
          : decision.resolvedDetections
                .where((hit) => !hit.requiresConfirmation)
                .map((hit) => hit.range);
      for (final range in ranges) {
        _block(range);
      }
      _report(FilterPhase.inspecting, '${decision.reason}，继续寻找可播放片段');
    }
  }

  void _block(RemovedInterval range) {
    // Round outward to output video frames; never retain a rejected frame edge.
    var from = Duration(milliseconds: (range.start.inMilliseconds ~/ 40) * 40);
    var to = Duration(
      milliseconds: ((range.end.inMilliseconds + 39) ~/ 40) * 40,
    );
    if (from < start) from = start;
    if (to > sourceDuration) to = sourceDuration;
    if (to <= from) return;
    if (from < _publishedThrough) {
      throw const FilterFailure('匹配超出隔离缓冲范围，已停止放行');
    }
    _blocked.add(RemovedInterval(from, to));
    _blocked.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < _blocked.length;) {
      final previous = _blocked[i - 1], current = _blocked[i];
      if (current.start <= previous.end) {
        _blocked[i - 1] = RemovedInterval(
          previous.start,
          current.end > previous.end ? current.end : previous.end,
        );
        _blocked.removeAt(i);
      } else {
        i++;
      }
    }
  }

  List<RemovedInterval> _safeParts(MediaSlice slice) {
    final result = <RemovedInterval>[];
    var cursor = slice.start;
    final end = slice.start + slice.duration;
    for (final range in _blocked) {
      if (range.end <= cursor || range.start >= end) continue;
      if (range.start > cursor) {
        result.add(RemovedInterval(cursor, range.start));
      }
      cursor = range.end < end ? range.end : end;
    }
    if (cursor < end) result.add(RemovedInterval(cursor, end));
    return result;
  }

  Future<void> _flush(Duration cutoff) async {
    while (_held.isNotEmpty &&
        _held.first.start + _held.first.duration <= cutoff) {
      cancellation.check();
      final slice = _held.removeAt(0);
      final parts = _safeParts(slice);
      final complete =
          parts.length == 1 &&
          parts.first.start == slice.start &&
          parts.first.end == slice.start + slice.duration;
      var allowed = Duration.zero;
      for (final part in parts) {
        await _waitForRoom();
        final length = part.end - part.start;
        final safe = complete
            ? slice
            : await sampler.crop(slice, part.start, length, cancellation);
        final file = await sampler.publish(
          safe,
          timeline.duration,
          cancellation,
        );
        cancellation.check();
        timeline.add(part.start, length, file.path);
        _publishedThrough = part.end;
        allowed += length;
        _report(FilterPhase.ready, '已放行检测通过的片段');
        if (!_ready.isCompleted && timeline.duration >= startupBuffer) {
          _ready.complete();
        }
      }
      _skipped += slice.duration - allowed;
      if (!complete && await slice.directory.exists()) {
        await slice.directory.delete(recursive: true);
      }
      await _prune();
    }
  }

  Future<void> _prune() async {
    final slices = timeline.slices;
    while (_prunedThrough < slices.length) {
      final slice = slices[_prunedThrough];
      if (slice.outputEnd + const Duration(seconds: 12) >= _outputPosition) {
        break;
      }
      final directory = File(slice.path).parent;
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
        _prunedThrough++;
      } on FileSystemException {
        // A native HTTP reader may still hold this file on Windows.
        break;
      }
    }
  }

  List<ApprovedSlice> get available => timeline.slices
      .where(
        (slice) =>
            slice.outputEnd + const Duration(seconds: 12) >= _outputPosition,
      )
      .toList();

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    cancellation.cancel();
    if (_wake?.isCompleted == false) _wake!.complete();
    await _running;
    await inspector.close();
    await _changes.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
