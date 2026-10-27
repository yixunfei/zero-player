import 'dart:async';

import 'cancellation_token.dart';
import 'header_policy.dart';

enum RequestPriority { playback, interactive, background }

final class RequestPermit {
  RequestPermit(this._release);
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Bounded global/per-origin concurrency. Playback goes ahead of queued
/// background work, without interrupting an already streaming response.
final class RequestScheduler {
  RequestScheduler({
    this.globalLimit = 8,
    this.originLimit = 2,
    this.playbackReserve = 0,
    this.backgroundLimit = 4,
  }) {
    if (globalLimit < 1 || originLimit < 1) {
      throw ArgumentError('Limits must be positive');
    }
  }
  final int globalLimit;
  final int originLimit;
  final int playbackReserve;
  final int backgroundLimit;
  int _background = 0;
  final _queue = <_WaitingRequest>[];
  final _origins = <String, int>{};
  int _active = 0;
  int _sequence = 0;
  bool _closed = false;

  Future<RequestPermit> acquire(
    Uri uri, {
    RequestPriority priority = RequestPriority.interactive,
    CancellationToken? cancellation,
  }) {
    if (_closed) throw StateError('Request scheduler closed');
    cancellation?.check();
    final pending = _WaitingRequest(
      HeaderPolicy.origin(uri),
      priority,
      _sequence++,
    );
    _queue.add(pending);
    pending.removeListener = cancellation?.listen(() {
      _queue.remove(pending);
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(const RequestCancelled());
      }
    });
    _drain();
    return pending.completer.future;
  }

  void _drain() {
    if (_closed) return;
    _queue.sort((a, b) {
      final priority = a.priority.index.compareTo(b.priority.index);
      return priority == 0 ? a.sequence.compareTo(b.sequence) : priority;
    });
    while (_active < globalLimit) {
      final index = _queue.indexWhere(
        (job) =>
            (_origins[job.origin] ?? 0) < originLimit &&
            (job.priority == RequestPriority.playback ||
                _active <
                    globalLimit - playbackReserve.clamp(0, globalLimit - 1)) &&
            (job.priority != RequestPriority.background ||
                _background < backgroundLimit),
      );
      if (index < 0) return;
      final job = _queue.removeAt(index);
      job.removeListener?.call();
      _active++;
      if (job.priority == RequestPriority.background) _background++;
      _origins.update(job.origin, (count) => count + 1, ifAbsent: () => 1);
      job.completer.complete(
        RequestPermit(() {
          _active--;
          if (job.priority == RequestPriority.background) _background--;
          final count = _origins[job.origin]! - 1;
          if (count == 0) {
            _origins.remove(job.origin);
          } else {
            _origins[job.origin] = count;
          }
          _drain();
        }),
      );
    }
  }

  void close() {
    _closed = true;
    for (final job in _queue) {
      job.removeListener?.call();
      job.completer.completeError(const RequestCancelled());
    }
    _queue.clear();
  }
}

final class _WaitingRequest {
  _WaitingRequest(this.origin, this.priority, this.sequence);
  final String origin;
  final RequestPriority priority;
  final int sequence;
  final completer = Completer<RequestPermit>();
  void Function()? removeListener;
}
