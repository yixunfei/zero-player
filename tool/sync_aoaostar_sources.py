"""Rebuild the offline Legado book-source catalog from a pinned release."""

import argparse
import bz2
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen


REPOSITORY = 'https://github.com/aoaostar/legado'
API = 'https://api.github.com/repos/aoaostar/legado'
REVISION = '116806ea5342f6590a818aa8da0c8bb826177583'
PACKS = {
    'b778fe6b': '全量书源',
    '71e56d4f': 'XIU2 精品书源',
    '4dc410d1': '破冰书源',
    'e3e5d620': '关耳女频',
    'e29e19ee': 'shidahuilang 书源',
    '2a1f129b': '酷安 · 三舞313书源',
    '3bb7b751': '酷安 · 开源阅读软件',
}


def fetch(url, accept='application/vnd.github+json'):
    request = Request(url, headers={'Accept': accept, 'User-Agent': 'Zero Player'})
    with urlopen(request, timeout=45) as response:
        return response.read()


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True)


def build(output, input_directory):
    tree = json.loads(fetch(f'{API}/git/trees/{REVISION}?recursive=1'))['tree']
    files = {row['path']: row for row in tree}
    records, index, membership, packs = [], {}, {}, []
    for pack_id, name in PACKS.items():
        path = f'sources/{pack_id}.json'
        blob = files[path]
        data = (
            (input_directory / f'{pack_id}.json').read_bytes()
            if input_directory else fetch(blob['url'], 'application/vnd.github.raw+json')
        )
        if hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest() != blob['sha']:
            raise ValueError(f'Git blob mismatch for {path}')
        rows = json.loads(data)
        if not isinstance(rows, list) or not rows or any(not isinstance(row, dict) for row in rows):
            raise ValueError(f'Invalid book-source list in {path}')
        references = []
        for row in rows:
            key = compact(row)
            if key not in index:
                index[key] = len(records)
                records.append(row)
            references.append(index[key])
        membership[pack_id] = references
        packs.append({
            'id': pack_id, 'name': name, 'count': len(rows),
            'sha256': hashlib.sha256(data).hexdigest(),
        })
    payload = compact({'records': records, 'packs': membership}).encode()
    archive = bz2.compress(payload)
    manifest = {
        'repository': REPOSITORY, 'revision': REVISION, 'packs': packs,
        'archiveSha256': hashlib.sha256(archive).hexdigest(),
        'records': len(records),
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / 'catalog.json.bz2').write_bytes(archive)
    (output / 'manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8', newline='\n',
    )
    print(f'{len(packs)} packs, {sum(pack["count"] for pack in packs)} rows, '
          f'{len(records)} distinct records, {len(archive)} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-directory', type=Path, help='Use locally downloaded Git blobs')
    parser.add_argument('--output', type=Path, default=Path('assets/catalogs/books/legado'))
    args = parser.parse_args()
    build(args.output, args.input_directory)
