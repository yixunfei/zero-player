import 'dart:async';
import 'dart:typed_data';

import 'cancellation_token.dart';
import 'document_client.dart';
import 'request_scheduler.dart';

/// The last visible consumer releases both queued and active network work.
final class PosterLease {
  PosterLease(this.bytes, this._release);
  final Future<Uint8List> bytes;
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Bounded shared compressed-image cache; Flutter bounds decoded images too.
final class PosterRepository {
  PosterRepository(
    this.network, {
    this.maxBytes = 16 * 1024 * 1024,
    this.maxEntries = 80,
    int concurrency = 4,
  }) : _scheduler = RequestScheduler(globalLimit: concurrency);
  final DocumentClient network;
  final int maxBytes;
  final int maxEntries;
  final RequestScheduler _scheduler;
  final _cache = <String, _CachedPoster>{};
  final _failures = <String, DateTime>{};
  final _pending = <String, _PendingPoster>{};
  int _cachedBytes = 0;
  bool _closed = false;
  int get cachedBytes => _cachedBytes;
  int get pendingCount => _pending.length;

  PosterLease acquire(String address) {
    if (_closed) throw StateError('Poster repository closed');
    final url = address.trim();
    final cached = _cache.remove(url);
    if (cached != null) {
      _cachedBytes -= cached.bytes.length;
      if (DateTime.now().difference(cached.created) <
          const Duration(minutes: 30)) {
        _remember(url, cached.bytes);
        return PosterLease(Future.value(cached.bytes), () {});
      }
    }
    final failed = _failures[url];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(minutes: 1)) {
      return PosterLease(
        Future.error(const FormatException('图片渠道暂不可用，请稍后重试')),
        () {},
      );
    }
    var pending = _pending[url];
    if (pending == null) {
      pending = _PendingPoster();
      _pending[url] = pending;
      pending.result = _fetch(url, pending);
    }
    final job = pending;
    job.readers++;
    return PosterLease(job.result, () {
      if (--job.readers == 0 && identical(_pending[url], job)) {
        _pending.remove(url);
        job.token.cancel();
      }
    });
  }

  Future<Uint8List> _fetch(String url, _PendingPoster job) async {
    RequestPermit? permit;
    try {
      final uri = Uri.parse(url);
      if (!{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('封面地址无效');
      }
      permit = await _scheduler.acquire(uri, cancellation: job.token);
      final doc = await network.get(
        uri,
        headers: posterHeaders(uri),
        maxBytes: 3 * 1024 * 1024,
        priority: RequestPriority.background,
        cancellation: job.token,
      );
      job.token.check();
      if (!isPosterPayload(doc.bytes)) {
        throw const FormatException('图片渠道返回了非图片内容');
      }
      final bytes = Uint8List.fromList(doc.bytes);
      if (!_closed) _remember(url, bytes);
      _failures.remove(url);
      return bytes;
    } catch (_) {
      if (!_closed && !job.token.isCancelled) {
        _failures.remove(url);
        _failures[url] = DateTime.now();
        while (_failures.length > maxEntries) {
          _failures.remove(_failures.keys.first);
        }
      }
      rethrow;
    } finally {
      permit?.release();
      if (identical(_pending[url], job)) _pending.remove(url);
    }
  }

  void _remember(String url, Uint8List bytes) {
    final old = _cache.remove(url);
    if (old != null) _cachedBytes -= old.bytes.length;
    if (bytes.length > maxBytes) return;
    _cache[url] = _CachedPoster(bytes, DateTime.now());
    _cachedBytes += bytes.length;
    while (_cachedBytes > maxBytes || _cache.length > maxEntries) {
      _cachedBytes -= _cache.remove(_cache.keys.first)!.bytes.length;
    }
  }

  void retry(String url) => _failures.remove(url.trim());
  void clear() {
    _cache.clear();
    _failures.clear();
    _cachedBytes = 0;
  }

  void close() {
    _closed = true;
    for (final job in _pending.values) {
      job.token.cancel();
    }
    _pending.clear();
    _scheduler.close();
    clear();
  }
}

Map<String, String> posterHeaders(Uri uri) => {
  'User-Agent': 'ZeroPlayer/0.1 (local media client)',
  'Accept': 'image/avif,image/webp,image/*;q=0.9,*/*;q=0.5',
  // Public image origin policy only. Never forward source credentials to CDNs.
  if (uri.host == 'doubanio.com' || uri.host.endsWith('.doubanio.com'))
    'Referer': 'https://movie.douban.com/',
};

bool isPosterPayload(List<int> b) {
  if (b.length < 12) return false;
  bool prefix(List<int> magic) =>
      List.generate(magic.length, (i) => b[i] == magic[i]).every((v) => v);
  return prefix([0xff, 0xd8, 0xff]) ||
      prefix([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) ||
      prefix([0x47, 0x49, 0x46, 0x38]) ||
      prefix([0x42, 0x4d]) ||
      (String.fromCharCodes(b.take(4)) == 'RIFF' &&
          String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') ||
      (String.fromCharCodes(b.sublist(4, 8)) == 'ftyp' &&
          {'avif', 'avis'}.contains(String.fromCharCodes(b.sublist(8, 12))));
}

final class _PendingPoster {
  final token = CancellationToken();
  late final Future<Uint8List> result;
  int readers = 0;
}

final class _CachedPoster {
  const _CachedPoster(this.bytes, this.created);
  final Uint8List bytes;
  final DateTime created;
}
