"""Validate native ABI completeness in an APK or Android App Bundle."""
import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
from android_package_version import verify_apk_version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file')
    parser.add_argument('--abis', default='arm64-v8a,x86_64')
    parser.add_argument('--max-mib', type=float, help='Fail if distributable exceeds this compressed size')
    parser.add_argument('--compressed-native', action='store_true', help='Require download-optimized native library compression')
    parser.add_argument('--debug', action='store_true', help='Debug APK uses a Dart kernel instead of libapp.so')
    parser.add_argument('--version', help='Expected embedded release version')
    parser.add_argument('--build-number', type=int, help='Expected Android versionCode')
    parser.add_argument('--aapt', help='Android SDK aapt executable')
    args = parser.parse_args()
    if (args.version is None) != (args.build_number is None):
        parser.error('--version and --build-number must be supplied together')
    if args.version is not None:
        if args.file.endswith('.aab'):
            parser.error('Embedded version verification requires an APK')
        verify_apk_version(args.file, args.version, args.build_number, args.aapt)
    prefix = 'base/lib/' if args.file.endswith('.aab') else 'lib/'
    with ZipFile(args.file) as archive:
        payload_bytes = sum(entry.compress_size for entry in archive.infolist())
        names = archive.namelist()
        files = set(names)
        if args.compressed_native and any(
            entry.compress_type != ZIP_DEFLATED
            for entry in archive.infolist()
            if entry.filename.startswith(prefix) and entry.filename.endswith('.so')
        ):
            raise SystemExit('Native libraries must be compressed in the phone APK')
    asset_prefix = 'base/assets/flutter_assets/' if args.file.endswith('.aab') else 'assets/flutter_assets/'
    for font in ['Xiaolai-Regular.ttf', 'NotoSansSC.ttf', 'NotoSerifSC.ttf']:
        if asset_prefix + 'assets/fonts/' + font not in files:
            raise SystemExit('Missing user-selectable font: ' + font)
    libraries = ['libflutter.so', 'libmpv.so', 'libffmpegkit.so', 'libsqlite3.so']
    if not args.debug:
        libraries.append('libapp.so')
    abis = {name[len(prefix):].split('/')[0] for name in files if name.startswith(prefix) and name.endswith('.so')}
    if abis != set(args.abis.split(',')):
        raise SystemExit('Unexpected ABI set: ' + str(abis))
    for abi in sorted(abis):
        for library in libraries:
            if names.count(prefix + abi + '/' + library) != 1:
                raise SystemExit('Missing or duplicate ' + library + ' for ' + abi)
    forbidden = ('libonnxruntime.so', 'libsherpa-onnx-c-api.so', 'libsherpa-onnx-cxx-api.so', '.onnx')
    if any(name.endswith(forbidden) for name in names):
        raise SystemExit('Optional inference runtime/model leaked into base package')
    file_bytes = Path(args.file).stat().st_size
    overhead = file_bytes - payload_bytes
    print(f'Package size: {file_bytes / 1048576:.2f} MiB; ZIP overhead: {overhead / 1048576:.2f} MiB')
    if args.max_mib is not None and file_bytes > args.max_mib * 1048576:
        raise SystemExit(f'Package exceeds {args.max_mib:g} MiB budget')
    if overhead > 8 * 1048576:
        print('WARNING: large ZIP padding; regenerate the packaging output before distribution')
    print('Optional inference libraries/models absent from base package')
    print('All three user-selectable fonts present')
    print('Native ABI completeness verified: ' + ', '.join(sorted(abis)))


if __name__ == '__main__':
    main()
