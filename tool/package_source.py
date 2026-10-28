"""Package the Git index only; ignored local files can never enter the source ZIP."""
from pathlib import Path
import io
import re
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parent.parent


def staged_files(tree):
    listing = subprocess.check_output(
        ['git', 'ls-tree', '-r', '-z', tree], cwd=ROOT
    ).decode('utf-8')
    forbidden = {'.tools', '.signing', '.git', 'build', 'artifacts', 'local.properties', 'key.properties'}
    files = []
    for entry in filter(None, listing.split('\0')):
        metadata, name = entry.split('\t', 1)
        mode, kind, object_id = metadata.split()
        path = Path(name)
        if any(part in forbidden for part in path.parts) or path.suffix in {'.jks', '.keystore', '.pem', '.p12'}:
            raise SystemExit('Forbidden local file in Git index: ' + name)
        if kind != 'blob' or mode not in {'100644', '100755'}:
            raise SystemExit('Unsupported non-regular source entry: ' + name)
        files.append((name, object_id))
    if not files:
        raise SystemExit('Stage reviewed source files with git add before packaging.')
    return files


def write_archive(target, files):
    # git archive applies checkout filters (including CRLF conversion). Read
    # immutable blobs in one batch so the ZIP contains the exact staged bytes.
    objects = '\n'.join(object_id for _, object_id in files) + '\n'
    batch = io.BytesIO(subprocess.check_output(
        ['git', 'cat-file', '--batch'], input=objects.encode('ascii'), cwd=ROOT,
    ))
    with ZipFile(target, 'w', ZIP_DEFLATED) as archive:
        for name, object_id in files:
            received, kind, length = batch.readline().decode('ascii').split()
            if received != object_id or kind != 'blob':
                raise RuntimeError('Unexpected Git object for ' + name)
            content = batch.read(int(length))
            if len(content) != int(length) or batch.read(1) != b'\n':
                raise RuntimeError('Incomplete Git object for ' + name)
            archive.writestr(name, content)


def main():
    # Freeze both file names and contents before reading the version or archiving.
    # ls-files alone lists staged names but archive.write would read worktree edits.
    tree = subprocess.check_output(['git', 'write-tree'], cwd=ROOT, text=True).strip()
    files = staged_files(tree)
    manifest = subprocess.check_output(
        ['git', 'show', tree + ':pubspec.yaml'], cwd=ROOT
    ).decode('utf-8')
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?:\+[^\s]+)?\s*$', manifest, re.M)
    if not match:
        raise SystemExit('Missing or invalid staged release version.')
    version = match[1]
    target = ROOT / 'artifacts/release' / version / ('zero-player-' + version + '-source.zip')
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=target.parent, suffix='.zip.part', delete=False) as output:
        temporary = Path(output.name)
    try:
        write_archive(temporary, files)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print(target)


if __name__ == '__main__':
    main()
