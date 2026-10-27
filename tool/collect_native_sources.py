"""Download audited upstream source snapshots and verify the recorded SHA-256."""
import hashlib
import json
from pathlib import Path
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def download(entry, target):
    file = target / entry['file']
    if file.exists():
        with file.open('rb') as existing:
            if hashlib.file_digest(existing, 'sha256').hexdigest() == entry['sha256']:
                return
    for attempt in range(3):
        try:
            with urllib.request.urlopen(entry['source'], timeout=120) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != entry['sha256']:
                raise ValueError('Source digest mismatch: ' + entry['file'])
            file.write_bytes(data)
            return
        except OSError:
            if attempt == 2:
                raise
            time.sleep(1)


def main():
    entries = json.loads((ROOT / 'tool/native_sources.json').read_text(encoding='utf-8'))
    target = ROOT / 'artifacts/native-sources'
    target.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        download(entry, target)
        print('Verified source:', entry['file'])
    (target / 'manifest.json').write_text(json.dumps(entries, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
