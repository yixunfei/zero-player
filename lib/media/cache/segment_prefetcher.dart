import 'dart:async';
import '../../core/network/header_policy.dart';
import '../hls/hls_manifest.dart';
import 'segment_fetcher.dart';

/// A small forward window. Shared fetches have their own lifetime; stopping
/// prefetch prevents new work without cancelling another playback/download lease.
final class SegmentPrefetcher {
  SegmentPrefetcher(this.fetcher, this.policy);
  final SegmentFetcher fetcher;
  final HeaderPolicy policy;
  int window = 3;
  int maxBytes = 256 * 1024 * 1024;
  bool whilePaused = false;
  bool enabled = false;
  bool playing = false;
  bool _closed = false;
  bool _running = false;
  int _index = 0;
  int _bytes = 0;
  final _seen = <String>{};
  List<Uri> _segments = [];
  bool get hasRoom => _bytes < maxBytes;
  void setManifest(HlsManifest manifest) {
    if (!manifest.isComplete ||
        manifest.segments.any((s) => s.byteRange != null)) {
      return;
    }
    _segments = manifest.segments.map((s) => s.uri).toList();
  }

  void observe(Uri uri, int bytes, {String? range}) {
    if (_seen.add('$uri|${range ?? ''}')) _bytes += bytes;
    final index = _segments.indexOf(uri);
    if (index >= 0) {
      _index = index + 1;
      kick();
    }
  }

  void kick() {
    if (_running ||
        _closed ||
        !enabled ||
        (!playing && !whilePaused) ||
        !hasRoom) {
      return;
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    final start = _index;
    try {
      for (var i = start; i < start + window && i < _segments.length; i++) {
        if (_closed || !hasRoom || (!playing && !whilePaused)) break;
        final uri = _segments[i];
        if (_seen.contains('$uri|')) continue;
        final lease = await fetcher.fetch(uri, policy);
        try {
          if (_seen.add('$uri|')) _bytes += lease.resource.length;
        } finally {
          lease.release();
        }
      }
    } catch (_) {
      /* Cache warming must never fail active playback. */
    } finally {
      _running = false;
    }
  }

  void close() => _closed = true;
}
