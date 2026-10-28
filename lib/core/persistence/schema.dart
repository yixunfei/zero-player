const schemaStatements = <String>[
  'CREATE TABLE IF NOT EXISTS app_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  '''CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS sources(
    id TEXT PRIMARY KEY, name TEXT NOT NULL, endpoint TEXT NOT NULL,
    kind TEXT NOT NULL, headers TEXT NOT NULL DEFAULT '{}',
    manual INTEGER NOT NULL DEFAULT 0, classification TEXT NOT NULL DEFAULT 'unknown',
    site_title TEXT, homepage TEXT)''',
  '''CREATE TABLE IF NOT EXISTS source_overrides(
    source_id TEXT PRIMARY KEY REFERENCES sources(id) ON DELETE CASCADE,
    name TEXT, enabled INTEGER NOT NULL DEFAULT 0, suppressed INTEGER NOT NULL DEFAULT 0)''',
  '''CREATE TABLE IF NOT EXISTS subscriptions(
    id TEXT PRIMARY KEY, name TEXT NOT NULL, url TEXT NOT NULL UNIQUE,
    refresh_hours INTEGER NOT NULL DEFAULT 24, last_success INTEGER,
    snapshot TEXT, error TEXT, paused INTEGER NOT NULL DEFAULT 0, failures INTEGER NOT NULL DEFAULT 0)''',
  '''CREATE TABLE IF NOT EXISTS source_memberships(
    subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    PRIMARY KEY(subscription_id,source_id))''',
  '''CREATE TABLE IF NOT EXISTS source_health(
    source_id TEXT PRIMARY KEY REFERENCES sources(id) ON DELETE CASCADE,
    failures INTEGER NOT NULL DEFAULT 0, last_error TEXT, checked_at INTEGER,
    retry_after INTEGER, latency_ms INTEGER, api_ok INTEGER NOT NULL DEFAULT 0, media_ok INTEGER NOT NULL DEFAULT 0)''',
  '''CREATE TABLE IF NOT EXISTS search_history(query TEXT PRIMARY KEY, used_at INTEGER NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS watch_history(
    id TEXT PRIMARY KEY, source_id TEXT NOT NULL, remote_id TEXT NOT NULL,
    title TEXT NOT NULL, year TEXT NOT NULL DEFAULT '', poster TEXT NOT NULL DEFAULT '',
    line_name TEXT NOT NULL, episode_label TEXT NOT NULL, position_ms INTEGER NOT NULL,
    duration_ms INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
  '''CREATE INDEX IF NOT EXISTS history_updated ON watch_history(updated_at DESC)''',
  '''CREATE TABLE IF NOT EXISTS skip_marks(
    id TEXT PRIMARY KEY, work_key TEXT NOT NULL, start_ms INTEGER NOT NULL,
    end_ms INTEGER NOT NULL, label TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
    duration_ms INTEGER NOT NULL, CHECK(start_ms>=0 AND end_ms>start_ms))''',
  '''CREATE TABLE IF NOT EXISTS skip_preferences(work_key TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE IF NOT EXISTS live_lists(
    id TEXT PRIMARY KEY, name TEXT NOT NULL, url TEXT NOT NULL,
    epg_url TEXT, snapshot TEXT, updated_at INTEGER, error TEXT)''',
  '''CREATE TABLE IF NOT EXISTS live_channels(
    id TEXT PRIMARY KEY, list_id TEXT NOT NULL REFERENCES live_lists(id) ON DELETE CASCADE,
    name TEXT NOT NULL, group_name TEXT NOT NULL DEFAULT '', logo TEXT NOT NULL DEFAULT '',
    tvg_id TEXT NOT NULL DEFAULT '', urls TEXT NOT NULL, headers TEXT NOT NULL DEFAULT '{}')''',
  '''CREATE TABLE IF NOT EXISTS channel_preferences(
    channel_id TEXT PRIMARY KEY, name TEXT NOT NULL, favorite INTEGER NOT NULL DEFAULT 0,
    watched_at INTEGER)''',
  '''CREATE TABLE IF NOT EXISTS epg_programs(
    source TEXT NOT NULL, channel_id TEXT NOT NULL, start_ms INTEGER NOT NULL,
    end_ms INTEGER NOT NULL, title TEXT NOT NULL,
    PRIMARY KEY(source,channel_id,start_ms))''',
  '''CREATE INDEX IF NOT EXISTS epg_time ON epg_programs(channel_id,start_ms,end_ms)''',
  '''CREATE TABLE IF NOT EXISTS downloads(
    id TEXT PRIMARY KEY, title TEXT NOT NULL, source_id TEXT, remote_id TEXT,
    line_name TEXT, episode_label TEXT, url TEXT NOT NULL, headers TEXT NOT NULL,
    status TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0, total INTEGER NOT NULL DEFAULT 0,
    bytes INTEGER NOT NULL DEFAULT 0, directory TEXT NOT NULL, local_path TEXT,
    fingerprint TEXT, error TEXT, created_at INTEGER NOT NULL, work_json TEXT)''',
  '''CREATE TABLE IF NOT EXISTS segment_index(
    cache_key TEXT PRIMARY KEY, path TEXT NOT NULL, bytes INTEGER NOT NULL,
    digest TEXT NOT NULL, status_code INTEGER NOT NULL, headers TEXT NOT NULL, used_at INTEGER NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS segment_references(
    owner TEXT NOT NULL, cache_key TEXT NOT NULL REFERENCES segment_index(cache_key) ON DELETE CASCADE,
    PRIMARY KEY(owner,cache_key))''',
  '''CREATE TABLE IF NOT EXISTS recommendation_cache(
    provider TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)''',
];
