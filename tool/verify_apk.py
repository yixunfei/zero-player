"""Validate native ABI completeness in an APK or Android App Bundle."""
import argparse
from zipfile import ZipFile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file')
    parser.add_argument('--abis', default='arm64-v8a,x86_64')
    args = parser.parse_args()
    prefix = 'base/lib/' if args.file.endswith('.aab') else 'lib/'
    with ZipFile(args.file) as archive:
        files = set(archive.namelist())
    abis = {name[len(prefix):].split('/')[0] for name in files if name.startswith(prefix) and name.endswith('.so')}
    if abis != set(args.abis.split(',')):
        raise SystemExit('Unexpected ABI set: ' + str(abis))
    for abi in sorted(abis):
        for library in ('libapp.so', 'libflutter.so', 'libmpv.so', 'libffmpegkit.so', 'libsqlite3.so'):
            if prefix + abi + '/' + library not in files:
                raise SystemExit('Missing ' + library + ' for ' + abi)
    print('Native ABI completeness verified: ' + ', '.join(sorted(abis)))


if __name__ == '__main__':
    main()
