"""Package the Git index only; ignored local files can never enter the source ZIP."""
from pathlib import Path
import re
import subprocess
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parent.parent


def main():
    version = re.search(r'^version: ([^+\s]+)', (ROOT / 'pubspec.yaml').read_text(), re.M)[1]
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    files = [name for name in tracked if name]
    if not files:
        raise SystemExit('Stage reviewed source files with git add before packaging.')
    forbidden = {'.tools', '.signing', '.git', 'build', 'artifacts', 'local.properties', 'key.properties'}
    for name in files:
        path = Path(name)
        if any(part in forbidden for part in path.parts) or path.suffix in {'.jks', '.keystore', '.pem', '.p12'}:
            raise SystemExit('Forbidden local file in Git index: ' + name)
    target = ROOT / 'artifacts/release' / version / ('zero-player-' + version + '-source.zip')
    target.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(target, 'w', ZIP_DEFLATED) as archive:
        for name in sorted(files):
            archive.write(ROOT / name, name)
    print(target)


if __name__ == '__main__':
    main()
