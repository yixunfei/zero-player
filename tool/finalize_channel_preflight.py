"""Freeze complete public/local media evidence without publishing user URLs or headers."""
import json
import hashlib
from datetime import datetime, timezone
from pathlib import Path


def freeze(records):
    merged = {}
    for row in records:
        routes = row['routes']
        urls = row['signature'].split('|')
        if len(routes) != len(urls) or [r['url'] for r in routes] != urls:
            raise ValueError('Incomplete route evidence: ' + row['id'])
        passed = [i for i, route in enumerate(routes) if route['availability'] == 'responding']
        if bool(passed) != (row['availability'] == 'responding'):
            raise ValueError('Availability disagrees with actual routes: ' + row['id'])
        frozen = {key: row.get(key) for key in ['id', 'requestSignature', 'checkedAt',
            'availability', 'latencyMs', 'message', 'resolution', 'languages']}
        frozen['verifiedIndices'] = passed
        preferred = min(passed, key=lambda i: routes[i]['latencyMs']
            if isinstance(routes[i].get('latencyMs'), int) else 999999) if passed else None
        frozen['preferredIndex'] = preferred
        if preferred is not None:
            for key in ['latencyMs', 'resolution', 'languages']:
                frozen[key] = routes[preferred].get(key)
        frozen['message'] = ('随包预检通过（媒体响应，非完整解码）' if passed else
            '随包预检：' + str(row.get('message') or '尚未确认媒体可用'))
        key = (row['id'], row['requestSignature'])
        old = merged.get(key)
        if old is None or old['checkedAt'] < frozen['checkedAt']:
            merged[key] = frozen
    return sorted(merged.values(), key=lambda row: (row['id'], row['requestSignature']))


def main():
    root = Path(__file__).resolve().parent.parent
    public = json.loads((root / 'build/channel-preflight-full.json').read_text(encoding='utf-8'))
    local = json.loads((root / 'build/local-channel-preflight-full.json').read_text(encoding='utf-8'))
    now = datetime.now(timezone.utc)
    for report in [public, local]:
        checked = datetime.fromisoformat(report['checkedAt'].replace('Z', '+00:00'))
        if not report['results'] or not 0 <= (now - checked).total_seconds() < 86400:
            raise ValueError('Complete reports from the last 24 hours are required')
    results = freeze([*public['results'], *local['results']])
    counts = {state: sum(row['availability'] == state for row in results)
        for state in ['responding', 'unavailable', 'inconclusive']}
    asset = {'version': 2, 'passedOnly': True,
        'checkedAt': datetime.now(timezone.utc).isoformat(),
        'scope': 'Full public built-in lists and local cached channels; every route tested; failed and inconclusive disabled until recovery test passes.',
        'managedListIds': sorted(set(public['managedListIds']) | {r['listId'] for r in local['results']} |
            {hashlib.sha256(r['url'].encode()).hexdigest() for r in public['sources']}),
        'counts': counts, 'sources': public['sources'], 'results': results}
    target = root / 'assets/live_channel_audit.json'
    temporary = target.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(asset, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(target)
    print(json.dumps({'publicChannels': len(public['results']), 'localChannels': len(local['results']),
        'uniqueChannelIds': len({row['id'] for row in results}), 'requestVersions': len(results), **counts}, ensure_ascii=False))


if __name__ == '__main__':
    main()
