"""Collect dependency notices without changing package caches."""
import hashlib
import json
import shutil
import tarfile
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent


def package_path(uri):
    parsed = urlparse(uri)
    if parsed.scheme == 'file':
        value = unquote(parsed.path)
        return Path(value[1:] if len(value) > 2 and value[2] == ':' else value)
    return (ROOT / '.dart_tool' / unquote(uri)).resolve()


def main():
    target = ROOT / 'artifacts' / 'notices'
    target.mkdir(parents=True, exist_ok=True)
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    inventory = []
    for package in config['packages']:
        if package['name'] == 'zero_player':
            continue
        directory = package_path(package['rootUri'])
        files = [f for f in directory.iterdir() if f.is_file()
                 and f.name.lower().startswith(('license', 'copying', 'notice'))]
        destination = target / 'dart-packages' / package['name']
        destination.mkdir(parents=True, exist_ok=True)
        for file in files:
            shutil.copy2(file, destination / file.name)
        inventory.append({'name': package['name'], 'package': directory.name,
                          'notices': [f.name for f in files]})
    native = ROOT / '.tools/ffmpegkit/unpacked/LICENSES'
    if native.exists():
        shutil.copytree(native, target / 'ffmpegkit-windows', dirs_exist_ok=True)
    collect_native_notices(target)
    (target / 'inventory.json').write_text(json.dumps(inventory, indent=2), encoding='utf-8')
    shutil.copy2(ROOT / 'NOTICE.md', target / 'NOTICE.md')
    print(f'Collected notices for {len(inventory)} packages in {target}')


def collect_native_notices(target):
    sources = ROOT / 'artifacts/native-sources'
    if not sources.exists():
        return
    manifest = sources / 'manifest.json'
    if manifest.exists():
        shutil.copy2(manifest, target / 'native-source-manifest.json')
    index = []
    for archive in sorted(sources.glob('*.tar.gz')):
        archive_key = (archive.name.removesuffix('.tar.gz')[:32] + '-'
                       + hashlib.sha256(archive.name.encode()).hexdigest()[:16])
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                path = Path(member.name)
                if (not member.isfile() or member.size > 1024 * 1024
                        or path.is_absolute() or '..' in path.parts
                        or not path.name.lower().startswith(('license', 'copying', 'notice'))):
                    continue
                # Preserve provenance in the index, not in deeply nested paths.
                member_key = hashlib.sha256(member.name.encode()).hexdigest()[:16]
                relative = Path('native-sources') / archive_key / (member_key + '-' + path.name[:48])
                destination = target / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                data = bundle.extractfile(member).read()
                destination.write_bytes(data)
                index.append({'archive': archive.name, 'member': member.name,
                              'notice': relative.as_posix(),
                              'sha256': hashlib.sha256(data).hexdigest()})
    (target / 'native-notice-index.json').write_text(
        json.dumps(index, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
