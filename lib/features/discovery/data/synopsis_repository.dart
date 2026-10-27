import 'dart:convert';
import 'package:html/parser.dart' as html;
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/request_scheduler.dart';
import '../../../core/persistence/app_database.dart';

/// Public subject pages only; never execute a verification page or substitute
/// another work's description. Requests are lazy, deduplicated and bounded.
final class SynopsisRepository {
  SynopsisRepository(this.network, this.db, {this.endpoint = subjectUri});
  final DocumentClient network;
  final AppDatabase db;
  final Uri Function(String) endpoint;
  final _cache = <String, (String, int)>{};
  final _failed = <String, DateTime>{};
  final _pending = <String, Future<String>>{};
  final _token = CancellationToken();
  final _scheduler = RequestScheduler(globalLimit: 2);
  Future<void>? _loaded;
  static const _key = 'cache:douban-synopses';

  Future<String> get(String id) async {
    _token.check();
    if (!RegExp(r'^[0-9]{1,12}$').hasMatch(id)) {
      throw const FormatException('作品标识无效');
    }
    await (_loaded ??= _restore());
    _token.check();
    final cached = _cache[id];
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - cached.$2 <
            const Duration(days: 7).inMilliseconds) {
      return cached.$1;
    }
    final failed = _failed[id];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(minutes: 5)) {
      throw const FormatException('简介暂无法获取');
    }
    final existing = _pending[id];
    if (existing != null) return existing;
    if (_pending.length >= 8) throw const FormatException('简介加载繁忙');
    final future = _fetch(id);
    _pending[id] = future;
    try {
      return await future;
    } finally {
      _pending.remove(id);
    }
  }

  Future<String> _fetch(String id) async {
    RequestPermit? permit;
    try {
      final uri = endpoint(id);
      permit = await _scheduler.acquire(uri, cancellation: _token);
      final doc = await network.get(
        uri,
        headers: const {'User-Agent': 'ZeroPlayer/0.1 (local media client)'},
        maxBytes: 512 * 1024,
        cancellation: _token,
        priority: RequestPriority.background,
      );
      _token.check();
      if (doc.uri.path != uri.path) throw const FormatException('详情页重定向');
      final text = parseSynopsis(doc.text);
      _cache.remove(id);
      _cache[id] = (text, DateTime.now().millisecondsSinceEpoch);
      while (_cache.length > 128) {
        _cache.remove(_cache.keys.first);
      }
      // A cache write failure must not discard a valid online result.
      try {
        await db.customStatement(
          'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
          [
            _key,
            jsonEncode({
              for (final entry in _cache.entries)
                entry.key: [entry.value.$1, entry.value.$2],
            }),
          ],
        );
      } catch (_) {
        /* A later request can still use the memory cache. */
      }
      return text;
    } catch (_) {
      if (!_token.isCancelled) {
        _failed[id] = DateTime.now();
        while (_failed.length > 128) {
          _failed.remove(_failed.keys.first);
        }
      }
      rethrow;
    } finally {
      permit?.release();
    }
  }

  Future<void> _restore() async {
    try {
      final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
        _key,
      ]);
      if (rows.isEmpty) return;
      final data = jsonDecode(rows.first['value'] as String);
      if (data is! Map) return;
      for (final entry in data.entries.take(128)) {
        final value = entry.value;
        if (entry.key is String &&
            value is List &&
            value.length == 2 &&
            value[0] is String &&
            (value[0] as String).length <= 8000 &&
            value[1] is int) {
          _cache[entry.key as String] = (value[0] as String, value[1] as int);
        }
      }
    } catch (_) {
      /* A malformed cache is expendable. */
    }
  }

  Future<void> close() async {
    _token.cancel();
    _scheduler.close();
    await Future.wait(
      _pending.values.map((f) => f.then<void>((_) {}, onError: (Object _) {})),
    );
    _cache.clear();
    _failed.clear();
  }
}

Uri subjectUri(String id) => Uri.https('movie.douban.com', '/subject/$id/');

String parseSynopsis(String source) {
  final document = html.parse(source);
  if (document.querySelector('form[action="/c"]') != null) {
    throw const FormatException('豆瓣需要验证，暂无法获取简介');
  }
  final summary = document.querySelector('[property="v:summary"]');
  final text = summary?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  if (text.isEmpty || text.length > 8000) {
    throw const FormatException('简介暂无法获取');
  }
  return text;
}
