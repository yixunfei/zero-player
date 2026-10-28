import 'dart:convert';

import '../../../core/network/document_client.dart';
import '../../../core/persistence/app_database.dart';
import '../domain/source_catalog.dart';
import '../domain/video_source.dart';
import 'source_identity_store.dart';
import 'source_preferences.dart';
import 'source_duplicate_store.dart';
import '../../supervision/application/content_policy.dart';

final class SourceRepository {
  const SourceRepository(
    this.db, {
    this.policy,
    this.authorize,
    this.canEnable,
  });
  final AppDatabase db;
  final ContentPolicy? policy;
  final void Function()? authorize;
  final bool Function()? canEnable;

  VideoSource _read(Map<String, Object?> row) {
    final source = VideoSource.fromRow(row);
    policy?.rememberSource(source);
    return source;
  }

  static const tables = {
    'sources',
    'source_overrides',
    'source_health',
    'source_memberships',
    'subscriptions',
    'app_meta',
  };
  Stream<void> get changes => db.changesFor(tables);
  static const _select = '''SELECT s.*, COALESCE(o.name,s.name) AS display_name,
    o.enabled,o.suppressed,h.failures,h.last_error,h.retry_after,h.api_ok,h.latency_ms,h.checked_at,
    f.value AS favorite,d.value AS diagnostics FROM sources s
    JOIN source_overrides o ON s.id=o.source_id LEFT JOIN source_health h ON s.id=h.source_id
    LEFT JOIN app_meta f ON f.key='source_favorite:'||s.id
    LEFT JOIN app_meta d ON d.key='source_diagnostic:'||s.id''';

  Future<void> favorite(String id, bool value) =>
      SourcePreferences(db).favorite(id, value);

  Future<String> preferredId(String id) =>
      SourceDuplicateStore(db).preferredId(id);

  Future<Map<String, String>> deduplicate({Set<String> preferred = const {}}) =>
      db.atomic(
        () => _deduplicate(preferred: preferred),
        tables: {...tables, 'settings'},
      );

  Future<Map<String, String>> _deduplicate({
    Set<String> preferred = const {},
  }) async =>
      SourceDuplicateStore(db).consolidate(await all(), preferred: preferred);

  Future<int> disablePossiblyInvalid(Iterable<String> confirmed) =>
      db.atomic(() async {
        final allowed = confirmed.toSet();
        final targets = (await all())
            .where(
              (s) => allowed.contains(s.id) && s.enabled && s.possiblyInvalid,
            )
            .map((s) => s.id)
            .toList();
        for (final id in targets) {
          await db.customStatement(
            'UPDATE source_overrides SET enabled=0 WHERE source_id=?',
            [id],
          );
        }
        return targets.length;
      }, tables: tables);

  Future<List<VideoSource>> all({bool includeSuppressed = false}) async =>
      (await db.rows(
        '''$_select
    WHERE ${includeSuppressed ? '1=1' : 'o.suppressed=0'} AND (s.manual=1 OR EXISTS(
    SELECT 1 FROM source_memberships m WHERE m.source_id=s.id)) ORDER BY display_name''',
      )).map(_read).toList();

  Future<VideoSource?> find(String id) async {
    final rows = await db.rows('$_select WHERE s.id=?', [id]);
    return rows.isEmpty ? null : _read(rows.first);
  }

  Future<String> saveManual(
    String name,
    Uri endpoint, {
    Map<String, String> headers = const {},
    bool enabled = true,
    String classification = 'unknown',
    String kind = 'cms',
  }) async {
    if (!{'http', 'https'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw const FormatException('请输入 HTTP(S) 接口地址');
    }
    if (!{'cms', 'kanju', 'macCmsHtml'}.contains(kind)) {
      throw const FormatException('不支持的来源类型');
    }
    return db.atomic(() async {
      authorize?.call();
      final id = await SourceIdentityStore(db).resolve(kind, endpoint);
      await db.customStatement(
        '''INSERT INTO sources(id,name,endpoint,kind,headers,manual,classification)
        VALUES(?,?,?,?,?,1,?) ON CONFLICT(id) DO UPDATE SET
        name=excluded.name,headers=excluded.headers,manual=1,classification=excluded.classification''',
        [
          id,
          name.trim(),
          endpoint.toString(),
          kind,
          jsonEncode(headers),
          classification,
        ],
      );
      await db.customStatement(
        '''INSERT INTO source_overrides(source_id,name,enabled,suppressed)
        VALUES(?,?,?,0) ON CONFLICT(source_id) DO UPDATE SET name=excluded.name,
        enabled=excluded.enabled,suppressed=0''',
        [id, name.trim(), enabled ? 1 : 0],
      );
      final merged = await _deduplicate();
      return merged[id] ?? id;
    }, tables: tables);
  }

  Future<void> setEnabled(String id, bool enabled) => db.atomic(() async {
    if (enabled) authorize?.call();
    await db.customStatement(
      'UPDATE source_overrides SET enabled=? WHERE source_id=?',
      [enabled ? 1 : 0, id],
    );
    if (enabled) {
      await db.customStatement('DELETE FROM source_health WHERE source_id=?', [
        id,
      ]);
    }
  }, tables: tables);
  Future<void> suppress(String id, bool suppressed) =>
      batch([id], suppressed: suppressed);
  Future<void> resetHealth(String id) =>
      db.write('DELETE FROM source_health WHERE source_id=?', [id]);

  Future<void> health(
    String id,
    RemoteFailure? failure, {
    int? latencyMs,
  }) async {
    if (failure?.kind == FailureKind.cancelled) {
      return;
    }
    final source = await find(id);
    final count = failure == null ? 0 : (source?.failures ?? 0) + 1;
    final now = DateTime.now();
    final wait = count >= 6
        ? const Duration(days: 7)
        : count >= 4
        ? const Duration(days: 1)
        : count >= 2
        ? const Duration(minutes: 30)
        : Duration.zero;
    await db.write(
      '''INSERT INTO source_health(source_id,failures,last_error,checked_at,retry_after,api_ok,latency_ms)
      VALUES(?,?,?,?,?,?,?) ON CONFLICT(source_id) DO UPDATE SET failures=excluded.failures,
      last_error=excluded.last_error,checked_at=excluded.checked_at,
      retry_after=excluded.retry_after,api_ok=excluded.api_ok,latency_ms=COALESCE(excluded.latency_ms,source_health.latency_ms)''',
      [
        id,
        count,
        failure?.message,
        now.millisecondsSinceEpoch,
        wait == Duration.zero ? null : now.add(wait).millisecondsSinceEpoch,
        failure == null ? 1 : 0,
        latencyMs,
      ],
    );
  }

  Future<void> batch(
    List<String> ids, {
    bool? enabled,
    bool? suppressed,
    bool deduplicateSources = true,
  }) => db.atomic(() async {
    if (enabled == true || suppressed == false) authorize?.call();
    for (final id in ids.toSet()) {
      if (enabled != null) {
        await db.customStatement(
          'UPDATE source_overrides SET enabled=? WHERE source_id=?',
          [enabled ? 1 : 0, id],
        );
        if (enabled) {
          await db.customStatement(
            'DELETE FROM source_health WHERE source_id=?',
            [id],
          );
        }
      }
      if (suppressed != null) {
        await db.customStatement(
          'UPDATE source_overrides SET suppressed=? WHERE source_id=?',
          [suppressed ? 1 : 0, id],
        );
      }
    }
    if (suppressed == false && deduplicateSources) {
      await _deduplicate(preferred: ids.toSet());
    }
  }, tables: tables);

  Future<void> metadata(String id, {String? title, Uri? homepage}) => db.write(
    'UPDATE sources SET site_title=COALESCE(?,site_title),homepage=COALESCE(?,homepage) WHERE id=?',
    [title, homepage?.toString(), id],
  );

  Future<void> applySubscription(
    Uri url,
    String name,
    String snapshot,
    List<SourceCandidate> candidates, {
    bool enableNew = false,
    Map<String, bool> initialEnabled = const {},
    bool replaceSources = true,
    bool deduplicateSources = true,
  }) => db.atomic(() async {
    final subscriptionId = stableId(url.toString());
    await db.customStatement(
      '''INSERT INTO subscriptions(id,name,url,last_success,snapshot)
      VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,
      last_success=excluded.last_success,snapshot=excluded.snapshot,error=NULL,
      paused=CASE WHEN subscriptions.failures>=3 THEN 0 ELSE subscriptions.paused END,failures=0''',
      [
        subscriptionId,
        name,
        url.toString(),
        DateTime.now().millisecondsSinceEpoch,
        snapshot,
      ],
    );
    if (replaceSources) {
      await db.customStatement(
        'DELETE FROM source_memberships WHERE subscription_id=?',
        [subscriptionId],
      );
    }
    for (final candidate in candidates) {
      final id = await SourceIdentityStore(
        db,
      ).resolve(candidate.kind.name, candidate.endpoint);
      await db.customStatement(
        '''INSERT INTO sources(id,name,endpoint,kind,classification) VALUES(?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET name=CASE WHEN sources.manual=1
        THEN sources.name ELSE excluded.name END,
        classification=CASE WHEN sources.classification='adult' OR excluded.classification='adult'
        THEN 'adult' WHEN sources.classification='unknown' THEN excluded.classification
        ELSE sources.classification END''',
        [
          id,
          candidate.name,
          candidate.endpoint.toString(),
          candidate.kind.name,
          candidate.classification,
        ],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO source_overrides(source_id,enabled) VALUES(?,?)',
        [
          id,
          (canEnable?.call() ?? true) &&
                  (initialEnabled[candidate.endpoint.toString()] ?? enableNew)
              ? 1
              : 0,
        ],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO source_memberships(subscription_id,source_id) VALUES(?,?)',
        [subscriptionId, id],
      );
    }
    if (deduplicateSources) await _deduplicate();
  }, tables: tables);

  Future<List<Map<String, Object?>>> subscriptions() =>
      db.rows('SELECT * FROM subscriptions ORDER BY name');
  Future<void> removeSubscription(String id) =>
      db.write('DELETE FROM subscriptions WHERE id=?', [id]);
  Future<void> pauseSubscription(String id, bool paused) => db.write(
    'UPDATE subscriptions SET paused=?,failures=0 WHERE id=?',
    [paused ? 1 : 0, id],
  );
  Future<void> subscriptionFailure(String id, String message) => db.write(
    '''UPDATE subscriptions SET error=?,
    failures=CASE WHEN paused=1 AND failures<3 THEN failures ELSE failures+1 END,
    paused=CASE WHEN failures>=2 THEN 1 ELSE paused END WHERE id=?''',
    [message, id],
  );
}
