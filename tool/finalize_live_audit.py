"""Verify a complete, URL-matched audit before producing packaged defaults."""
import collections
import datetime
import json
import pathlib
import sqlite3

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    database = ROOT / 'artifacts/live-audit-20261028.sqlite'
    with sqlite3.connect(f'file:{database.as_posix()}?mode=ro', uri=True) as db:
        channels = {r[0]: '|'.join(json.loads(r[1])) for r in db.execute(
            'SELECT id,urls FROM live_channels')}
        lists = {r[0]: r[1] for r in db.execute('SELECT id,url FROM live_lists')}
        metadata = [json.loads(r[0]) for r in db.execute(
            "SELECT value FROM app_meta WHERE key LIKE 'live_metadata:%'")]
    rows = [json.loads(line) for line in (ROOT / 'artifacts/live-audit-20261028.jsonl').read_text(encoding='utf-8').splitlines()]
    records = {r['id']: r for r in rows if channels.get(r['id']) == r['signature']}
    missing = channels.keys() - records.keys()
    if missing:
        raise SystemExit(f'Audit incomplete: {len(missing)} channel sources missing')
    builtin_urls = {e['url'] for e in json.loads((ROOT / 'assets/live_candidates.json').read_text(encoding='utf-8'))['lists']}
    bundled = sorted((r for r in records.values() if lists[r['listId']] in builtin_urls), key=lambda r: r['id'])
    checked_at = datetime.datetime.fromtimestamp(max(r['checkedAt'] for r in records.values()) / 1000, datetime.timezone.utc).isoformat()
    report = {
        'checkedAt': checked_at,
        'scope': 'Media payload response on this machine; up to 3 URLs per source, 256 KiB and 8 seconds active transport per URL. No full decode or continuous uptime guarantee.',
        'policy': 'Only explicit unavailable results default to disabled. Inconclusive results retain enabled state; user may disable them in one action.',
        'results': bundled,
    }
    (ROOT / 'assets/live_channel_audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    summary = {
        'checkedAt': checked_at, 'sources': len(records),
        'availability': dict(collections.Counter(r['availability'] for r in records.values())),
        'byList': {name: dict(collections.Counter(r['availability'] for r in records.values() if r['listName'] == name)) for name in sorted({r['listName'] for r in records.values()})},
        'streamResolutions': dict(collections.Counter(r['resolution'] for r in records.values() if r['resolution'])),
        'declaredLanguages': sum(bool(r.get('languages')) for r in metadata),
        'declaredCategories': sum(bool(r.get('categories')) for r in metadata),
    }
    (ROOT / 'artifacts/live-audit-summary-20261028.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == '__main__':
    main()
