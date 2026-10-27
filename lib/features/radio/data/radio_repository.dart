import 'dart:convert';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/persistence/app_database.dart';
import '../../live/data/live_playlist_parser.dart';
import '../../live/domain/live_channel.dart';

const builtinRadioUrl =
    'https://raw.githubusercontent.com/popocoding/awesome-m3u/refs/heads/main/radio/cn.m3u';

final class RadioCatalog {
  const RadioCatalog(this.stations, this.updatedAt, {this.notice});
  final List<LiveChannel> stations;
  final DateTime updatedAt;
  final String? notice;
}

/// Radio snapshots have their own namespace and never enter the TV database.
final class RadioRepository {
  RadioRepository(this.db, this.network, {Uri? source})
    : source = source ?? Uri.parse(builtinRadioUrl);
  final AppDatabase db;
  final DocumentClient network;
  final Uri source;
  String get _key => 'radio_snapshot:$source';

  Future<RadioCatalog> load({
    bool refresh = false,
    CancellationToken? cancellation,
  }) async {
    final cached = await _cached();
    cancellation?.check();
    final age = cached == null
        ? null
        : DateTime.now().difference(cached.updatedAt);
    if (!refresh &&
        age != null &&
        !age.isNegative &&
        age < const Duration(hours: 24)) {
      return cached!;
    }
    try {
      final doc = await network.get(
        source,
        maxBytes: 4 * 1024 * 1024,
        cancellation: cancellation,
        networkTimeout: const Duration(seconds: 15),
      );
      final stations = parseLivePlaylist(doc.text, doc.uri, 'radio');
      if (stations.isEmpty) throw const FormatException('广播列表为空');
      cancellation?.check();
      final now = DateTime.now();
      await db.write('INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)', [
        _key,
        jsonEncode({
          'text': doc.text,
          'base': doc.uri.toString(),
          'updatedAt': now.millisecondsSinceEpoch,
        }),
      ]);
      return RadioCatalog(stations, now);
    } catch (_) {
      cancellation?.check();
      if (cached != null) {
        return RadioCatalog(
          cached.stations,
          cached.updatedAt,
          notice: '更新失败，正在使用上次成功获取的列表；可稍后重试。',
        );
      }
      rethrow;
    }
  }

  Future<RadioCatalog?> _cached() async {
    final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
      _key,
    ]);
    if (rows.isEmpty) return null;
    try {
      final data =
          jsonDecode(rows.single['value'] as String) as Map<String, dynamic>;
      final stations = parseLivePlaylist(
        data['text'] as String,
        Uri.parse(data['base'] as String),
        'radio',
      );
      if (stations.isEmpty) return null;
      return RadioCatalog(
        stations,
        DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
