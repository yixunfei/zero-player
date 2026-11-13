"""Verify the pinned PDFium release archive and library; no system DLL lookup."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['win-x64', 'android-x64', 'android-arm64'])
    parser.add_argument('library', type=Path)
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    pins = json.loads(Path(__file__).with_name('pdfium_checksums.json').read_text())[args.platform]
    for file, expected in [(args.library, pins['librarySha256']), *(([(args.archive, pins['archiveSha256'])]) if args.archive else [])]:
        actual = hashlib.file_digest(file.open('rb'), 'sha256').hexdigest()
        if actual != expected:
            raise SystemExit(f'PDFium checksum mismatch: {file}')
        print(f'Verified {file}: {actual}')


if __name__ == '__main__':
    main()
