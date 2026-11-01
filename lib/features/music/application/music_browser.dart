import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/persistence/app_database.dart';
import '../../supervision/domain/supervision_rules.dart';
import '../data/music_repository.dart';
import 'music_multi_search.dart';
import '../data/public_music_sources.dart';
import '../domain/music_track.dart';

final class MusicBrowser extends ChangeNotifier {
  MusicBrowser(this.repository, {this.db});
  final MusicRepository repository;
  final AppDatabase? db;
  Future<void>? _loaded;
  Future<void> _writes = Future.value();
  int _choiceRevision = 0;
  CancellationToken? _request;
  bool _closed = false;
  String query = '';
  String _provider = 'myfreemp3';
  String get provider => _provider;
  int page = 1;
  bool loading = false;
  String? error;
  String? sourceNotice;
  int completedSources = 0;
  int failedSources = 0;
  String? preferenceNotice;
  MusicSearchResult result = const MusicSearchResult([]);
  Future<void> load() => _loaded ??= _restoreProvider();
  Future<void> _restoreProvider() async {
    final revision = _choiceRevision;
    try {
      final rows = await db?.rows(
        "SELECT value FROM app_meta WHERE key='music_provider'",
      );
      if (_closed ||
          revision != _choiceRevision ||
          rows == null ||
          rows.isEmpty) {
        return;
      }
      final value = jsonDecode(rows.first['value'] as String);
      if (value is String &&
          (value == 'all' || musicSources.containsKey(value))) {
        _provider = value;
        notifyListeners();
      }
    } catch (_) {
      // A damaged local preference must not prevent searching.
    }
  }

  void selectProvider(String value) {
    if (_closed || !(value == 'all' || musicSources.containsKey(value))) return;
    final revision = ++_choiceRevision;
    _provider = value;
    preferenceNotice = null;
    if (db != null) {
      _writes = _writes
          .then(
            (_) => db!.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
              'music_provider',
              jsonEncode(value),
            ]),
          )
          .catchError((Object _) {
            if (!_closed && revision == _choiceRevision) {
              preferenceNotice = '渠道选择未能保存，本次仍可使用。';
              notifyListeners();
            }
          });
    }
    if (query.isNotEmpty) {
      unawaited(search(query));
    } else {
      notifyListeners();
    }
  }

  Future<void> search(String value, {int page = 1}) async {
    if (_closed) return;
    _request?.cancel();
    final token = _request = CancellationToken();
    query = value.trim();
    this.page = page;
    loading = true;
    error = null;
    sourceNotice = null;
    completedSources = failedSources = 0;
    result = const MusicSearchResult([]);
    notifyListeners();
    try {
      await load();
      if (_closed || token.isCancelled) return;
      if (provider == 'all') {
        final tracks = <String, MusicTrack>{};
        var hasNext = false;
        await MusicMultiSearch(repository.search).run(
          query,
          page: page,
          cancellation: token,
          onResult: (source, response, failure) {
            if (_closed || token.isCancelled) return;
            completedSources++;
            if (failure != null) failedSources++;
            if (response != null) {
              for (final track in response.tracks) {
                tracks.putIfAbsent(track.key, () => track);
              }
              hasNext = hasNext || response.hasNext;
            }
            result = MusicSearchResult(
              List.unmodifiable(tracks.values),
              hasNext: hasNext,
            );
            sourceNotice =
                '已完成 $completedSources/${MusicMultiSearch.providers.length} 个渠道'
                '${failedSources > 0 ? ' · $failedSources 个不可用或被过滤' : ''}';
            notifyListeners();
          },
        );
        if (!_closed &&
            !token.isCancelled &&
            failedSources == MusicMultiSearch.providers.length) {
          error = '所有音乐渠道暂不可用或已被过滤，可播放本地下载或重试。';
        }
        return;
      }
      final response = await repository.search(
        query,
        page: page,
        cancellation: token,
        provider: provider,
      );
      if (_closed || token.isCancelled) return;
      result = response;
    } catch (failure) {
      if (_closed || token.isCancelled) return;
      error = switch (failure) {
        ContentBlocked() => '搜索内容或音乐渠道已被当前过滤规则屏蔽。',
        FormatException() => failure.message,
        RemoteFailure() => failure.message,
        _ => '音乐渠道连接失败，请检查网络后重试。',
      };
    } finally {
      if (!_closed && !token.isCancelled) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> close() async {
    if (!_closed) dispose();
    await _loaded;
    await _writes;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _request?.cancel();
    super.dispose();
  }
}
