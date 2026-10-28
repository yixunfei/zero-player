import 'dart:convert';

import '../../../core/network/document_client.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/persistence/app_database.dart';
import '../../sources/domain/video_source.dart';
import '../domain/live_channel.dart';
import 'epg_parser.dart';
import 'live_playlist_parser.dart';
import 'playlist_channels.dart';
import 'playlist_epg.dart';
import 'live_audit_defaults.dart';
import '../domain/live_health.dart';
import '../domain/live_metadata.dart';
import '../domain/channel_merge.dart';
import '../domain/epg_channel_match.dart';

final class LiveRepository {
  const LiveRepository(this.db, this.network, {this.defaults});
  final AppDatabase db;
  final DocumentClient network;
  final LiveAuditDefaults? defaults;

  Future<List<Map<String, Object?>>> lists() => db.rows(
    '''SELECT l.*, CASE WHEN m.value='false' THEN 0 ELSE 1 END AS enabled
        FROM live_lists l LEFT JOIN app_meta m ON m.key='live_list_enabled:'||l.id
        ORDER BY l.name''',
  );
  Future<void> setListEnabled(String id, bool enabled) => db.write(
    'INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)',
    ['live_list_enabled:$id', jsonEncode(enabled)],
  );
  Future<void> removeList(String id) =>
      db.write('DELETE FROM live_lists WHERE id=?', [id]);

  Future<void> import(
    String name,
    Uri url, {
    Uri? epg,
    Map<String, String> headers = const {},
    CancellationToken? cancellation,
    bool existingOnly = false,
  }) async {
    final id = stableId(url.toString());
    try {
      if (headers.isEmpty) {
        final saved = await db.rows('SELECT value FROM app_meta WHERE key=?', [
          'live_headers:$id',
        ]);
        if (saved.isNotEmpty) {
          headers = Map<String, String>.from(
            jsonDecode(saved.first['value'] as String),
          );
        }
      }
      final doc = await network.get(
        url,
        headers: headers,
        cancellation: cancellation,
        maxBytes: 8 * 1024 * 1024,
      );
      epg ??= await _guide(id) ?? playlistEpg(doc.text, doc.uri);
      await importText(
        name,
        url,
        doc.text,
        base: doc.uri,
        epg: epg,
        headers: headers,
        existingOnly: existingOnly,
        cancellation: cancellation,
      );
    } catch (_) {
      if (cancellation?.isCancelled != true) {
        await db.write('UPDATE live_lists SET error=? WHERE id=?', [
          '更新失败，保留旧列表',
          id,
        ]);
      }
      rethrow;
    }
    if (epg != null) {
      try {
        await refreshEpg(epg, cancellation: cancellation);
      } catch (_) {
        cancellation?.check();
        await db.write('UPDATE live_lists SET error=? WHERE id=?', [
          '频道已更新，EPG 更新失败',
          id,
        ]);
      }
    }
  }

  Future<void> importText(
    String name,
    Uri url,
    String text, {
    Uri? base,
    Uri? epg,
    Map<String, String> headers = const {},
    bool existingOnly = false,
    CancellationToken? cancellation,
  }) async {
    final id = stableId(url.toString());
    final channels = parseLivePlaylist(text, base ?? url, id);
    if (channels.isEmpty) throw const FormatException('频道列表为空，保留旧列表');
    epg ??= await _guide(id) ?? playlistEpg(text, base ?? url);
    final audit = await defaults?.entries;
    await db.atomic(() async {
      cancellation?.check();
      if (existingOnly &&
          (await db.rows('SELECT id FROM live_lists WHERE id=?', [
            id,
          ])).isEmpty) {
        return;
      }
      await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
        'live_headers:$id',
        jsonEncode(headers),
      ]);
      await db.customStatement(
        '''INSERT INTO live_lists(id,name,url,epg_url,snapshot,updated_at)
          VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,
          epg_url=COALESCE(excluded.epg_url,live_lists.epg_url),snapshot=excluded.snapshot,updated_at=excluded.updated_at,error=NULL''',
        [
          id,
          name,
          url.toString(),
          epg?.toString(),
          text,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      final previous = await db.rows(
        'SELECT * FROM live_channels WHERE list_id=?',
        [id],
      );
      final prepared = preparePlaylistChannels(channels, previous, headers);
      if (audit != null) await defaults!.apply(db, prepared, audit);
      await db.customStatement('DELETE FROM live_channels WHERE list_id=?', [
        id,
      ]);
      for (final c in prepared) {
        await db.customStatement(
          'INSERT OR REPLACE INTO app_meta VALUES(?,?)',
          [
            'live_metadata:${c.id}',
            jsonEncode({...c.metadata.toJson(), 'signature': c.urls.join('|')}),
          ],
        );
        await db.customStatement(
          '''INSERT INTO live_channels(id,list_id,name,group_name,logo,tvg_id,urls,headers)
            VALUES(?,?,?,?,?,?,?,?)''',
          [
            c.id,
            id,
            c.name,
            c.group,
            c.logo,
            c.tvgId,
            jsonEncode(c.urls.map((u) => u.toString()).toList()),
            jsonEncode({...headers, ...c.headers}),
          ],
        );
      }
    });
  }

  Future<List<LiveChannel>> channels() async {
    final rows = await db.rows(
      '''SELECT c.*,p.favorite,p.watched_at,l.name AS list_name,m.value AS health,d.value AS metadata FROM live_channels c
      JOIN live_lists l ON l.id=c.list_id
      LEFT JOIN channel_preferences p ON c.id=p.channel_id
      LEFT JOIN app_meta m ON m.key='live_state:'||c.id
      LEFT JOIN app_meta d ON d.key='live_metadata:'||c.id
      LEFT JOIN app_meta s ON s.key='live_list_enabled:'||l.id
      WHERE s.value IS NULL OR s.value!='false' ''',
    );
    final available = rows
        .map(
          (r) => LiveChannel(
            id: r['id'] as String,
            listId: r['list_id'] as String,
            name: r['name'] as String,
            group: r['group_name'] as String,
            logo: r['logo'] as String,
            tvgId: r['tvg_id'] as String,
            urls: (jsonDecode(r['urls'] as String) as List)
                .map((u) => Uri.parse(u as String))
                .toList(),
            headers: Map<String, String>.from(
              jsonDecode(r['headers'] as String),
            ),
            favorite: r['favorite'] == 1,
            recent: r['watched_at'] != null,
            watchedAt: r['watched_at'] is int
                ? DateTime.fromMillisecondsSinceEpoch(r['watched_at'] as int)
                : null,
            listName: r['list_name'] as String,
            metadata: LiveMetadata.decode(
              r['metadata'],
              (jsonDecode(r['urls'] as String) as List)
                  .map((u) => Uri.parse(u as String))
                  .toList(),
            ),
            health: LiveHealth.decode(
              r['health'],
              (jsonDecode(r['urls'] as String) as List)
                  .map((u) => Uri.parse(u as String))
                  .toList(),
            ),
          ),
        )
        .toList();
    final missing = await db.rows(
      '''SELECT p.*,m.value AS health FROM channel_preferences p
      LEFT JOIN app_meta m ON m.key='live_state:'||p.channel_id
      WHERE p.favorite=1 AND NOT EXISTS(SELECT 1 FROM live_channels c WHERE c.id=p.channel_id)''',
    );
    final result = [
      ...available,
      for (final row in missing)
        LiveChannel(
          id: row['channel_id'] as String,
          listId: '',
          name: row['name'] as String,
          urls: const [],
          favorite: true,
          group: '暂不可用',
          listName: '订阅中暂无此频道',
          health: LiveHealth.decode(row['health'], const []),
        ),
    ];
    return mergeChannelAliases(result);
  }

  Future<void> favorite(LiveChannel channel, bool value) => db.atomic(() async {
    for (final entry in channel.entries) {
      await db.customStatement(
        '''INSERT INTO channel_preferences(channel_id,name,favorite)
        VALUES(?,?,?) ON CONFLICT(channel_id) DO UPDATE SET favorite=excluded.favorite,name=excluded.name''',
        [entry.id, entry.name, value ? 1 : 0],
      );
    }
  });
  Future<void> watched(LiveChannel channel) => db.atomic(() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in channel.entries) {
      await db.customStatement(
        '''INSERT INTO channel_preferences(channel_id,name,watched_at)
        VALUES(?,?,?) ON CONFLICT(channel_id) DO UPDATE SET watched_at=excluded.watched_at,name=excluded.name''',
        [entry.id, entry.name, now],
      );
    }
  });

  Future<void> refreshEpg(Uri url, {CancellationToken? cancellation}) async {
    final doc = await network.get(
      url,
      maxBytes: 20 * 1024 * 1024,
      gzip: url.path.endsWith('.gz'),
      cancellation: cancellation,
    );
    final programs = await parseEpgInBackground(
      doc.text,
      DateTime.now().toUtc(),
    );
    await db.atomic(() async {
      cancellation?.check();
      await db.customStatement('DELETE FROM epg_programs WHERE source=?', [
        url.toString(),
      ]);
      for (var offset = 0; offset < programs.length; offset += 500) {
        cancellation?.check();
        await db.batch((batch) {
          for (final program in programs.skip(offset).take(500)) {
            batch.customStatement(
              'INSERT OR REPLACE INTO epg_programs VALUES(?,?,?,?,?)',
              [
                url.toString(),
                program.channelId,
                program.start.millisecondsSinceEpoch,
                program.end.millisecondsSinceEpoch,
                program.title,
              ],
            );
          }
        });
      }
    }, tables: const {'epg_programs'});
  }

  Future<List<EpgProgram>> schedule(LiveChannel channel) async {
    for (final entry in channel.entries) {
      final programs = await _scheduleEntry(entry);
      if (programs.isNotEmpty) return programs;
    }
    return [];
  }

  Future<Uri?> _guide(String listId) async {
    final rows = await db.rows('SELECT epg_url FROM live_lists WHERE id=?', [
      listId,
    ]);
    final value = rows.firstOrNull?['epg_url'];
    return value is String && value.isNotEmpty ? Uri.tryParse(value) : null;
  }

  Future<void> refreshSchedule(LiveChannel channel) async {
    final urls = <Uri>{};
    for (final entry in channel.entries) {
      final guide = await _guide(entry.listId);
      if (guide != null) urls.add(guide);
    }
    final queue = urls.toList();
    final errors = <Object>[];
    var cursor = 0, successes = 0;
    var found = false;
    Future<void> worker() async {
      while (cursor < queue.length && !found) {
        final uri = queue[cursor++];
        try {
          await refreshEpg(uri);
          successes++;
          found = (await schedule(channel)).isNotEmpty;
        } catch (error) {
          errors.add(error);
        }
      }
    }

    await Future.wait(List.generate(queue.length.clamp(0, 2), (_) => worker()));
    if (successes == 0 && errors.isNotEmpty) throw errors.first;
  }

  Future<List<EpgProgram>> _scheduleEntry(LiveChannel channel) async {
    final list = await db.rows('SELECT epg_url FROM live_lists WHERE id=?', [
      channel.listId,
    ]);
    if (list.isEmpty || list.first['epg_url'] == null) return [];
    var id = channel.tvgId;
    if (id.isEmpty) {
      final ids = await db.rows(
        'SELECT DISTINCT channel_id FROM epg_programs WHERE source=?',
        [list.first['epg_url']],
      );
      id =
          matchEpgChannel(
            '',
            channel.name,
            ids.map((r) => r['channel_id'] as String),
          ) ??
          '';
      if (id.isEmpty) return [];
    }
    final rows = await db.rows(
      '''SELECT * FROM epg_programs WHERE source=? AND channel_id=? AND end_ms>?
      ORDER BY start_ms LIMIT 48''',
      [list.first['epg_url'], id, DateTime.now().millisecondsSinceEpoch],
    );
    return rows
        .map(
          (r) => EpgProgram(
            r['channel_id'] as String,
            r['title'] as String,
            DateTime.fromMillisecondsSinceEpoch(
              r['start_ms'] as int,
              isUtc: true,
            ),
            DateTime.fromMillisecondsSinceEpoch(
              r['end_ms'] as int,
              isUtc: true,
            ),
            matchedByName: channel.tvgId.isEmpty,
            sourceUrl: list.first['epg_url'] as String,
          ),
        )
        .toList();
  }
}
