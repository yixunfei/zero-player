"""Check the APK's embedded version with the configured Android SDK."""
from pathlib import Path
import os
import re
import subprocess


def find_aapt(root):
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    properties = root / 'android/local.properties'
    if properties.exists():
        match = re.search(r'^sdk.dir=(.+)$', properties.read_text(), re.M)
        if match:
            sdk = match[1].strip().replace(chr(92) * 2, chr(92)).replace(chr(92) + ':', ':')
    if not sdk:
        raise ValueError('Android SDK not configured; provide --aapt')
    candidates = list((Path(sdk) / 'build-tools').glob('*/aapt.exe' if os.name == 'nt' else '*/aapt'))
    if not candidates:
        raise ValueError('Android SDK aapt not found; provide --aapt')
    return max(candidates, key=lambda p: tuple(int(n) for n in re.findall(r'[0-9]+', p.parent.name)))


def check_badging(text, version, build_number):
    match = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", text, re.M)
    if not match or match[1] != 'dev.zeroplayer.zero_player':
        raise ValueError('APK application ID does not match Zero Player')
    if match[2] != str(build_number) or match[3] != version:
        raise ValueError(f'APK version {match[3]}+{match[2]} does not match {version}+{build_number}')


def verify_apk_version(file, version, build_number, aapt=None):
    command = aapt or find_aapt(Path(__file__).resolve().parent.parent)
    result = subprocess.run([str(command), 'dump', 'badging', str(file)],
                            capture_output=True, text=True, encoding='utf-8', check=True)
    check_badging(result.stdout, version, build_number)
    print(f'Embedded APK version verified: {version}+{build_number}')
