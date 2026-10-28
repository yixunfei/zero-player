"""Create a consistent SQLite backup before explicit local maintenance."""
import argparse
import json
from pathlib import Path
import sqlite3


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('database', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    source = args.database.resolve(strict=True)
    output = args.output.resolve()
    if output.exists():
        raise SystemExit('Backup destination already exists; refusing overwrite.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as original:
        with sqlite3.connect(output) as backup:
            original.backup(backup)
            integrity = backup.execute('PRAGMA integrity_check').fetchone()[0]
            if integrity != 'ok':
                raise SystemExit('Backup integrity check failed.')
    print(json.dumps({'backup': str(output), 'integrity': integrity}))


if __name__ == '__main__':
    main()
