import 'dart:async';
import '../../core/network/header_policy.dart';
import '../hls/hls_manifest.dart';
import 'segment_fetcher.dart';
import 'resource_identity.dart';

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
  final _seen = <String, int>{};
  List<Uri> _segments = [];
  int get _residentBytes {
    _seen.removeWhere((key, _) => fetcher.store.find(key) == null);
    return _seen.values.fold(0, (sum, bytes) => sum + bytes);
  }

  bool get hasRoom => _residentBytes < maxBytes;

  Future<bool> prepare() async {
    if (_closed || maxBytes <= 0) return false;
    final bytes = _residentBytes;
    if (bytes >= maxBytes) {
      try {
        await fetcher.store.evictUnused(
          _seen.keys.toList(),
          bytes - maxBytes + 1,
        );
      } catch (_) {
        return false;
      }
    }
    return hasRoom;
  }

  void setManifest(HlsManifest manifest) {
    if (!manifest.isComplete ||
        manifest.segments.any((s) => s.byteRange != null)) {
      return;
    }
    _segments = manifest.segments.map((s) => s.uri).toList();
  }

  void observe(Uri uri, int bytes, {String? range}) {
    final key = resourceIdentity(uri, policy.identityHeaders, range);
    _seen.remove(key);
    _seen[key] = bytes;
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
        maxBytes <= 0) {
      return;
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    final start = _index;
    try {
      for (var i = start; i < start + window && i < _segments.length; i++) {
        if (_closed || (!playing && !whilePaused) || !await prepare()) break;
        final uri = _segments[i];
        final key = resourceIdentity(uri, policy.identityHeaders, null);
        if (fetcher.store.find(key) != null) continue;
        final lease = await fetcher.fetch(uri, policy);
        try {
          _seen[key] = lease.resource.length;
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
