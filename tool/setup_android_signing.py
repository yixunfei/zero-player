"""Create a private local release key on explicit invocation; never print secrets."""
import argparse
import os
from pathlib import Path
import secrets
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create', action='store_true', required=True)
    parser.parse_args()
    config = ROOT / 'android/key.properties'
    if config.exists():
        print('Existing android/key.properties preserved.')
        return
    folder = Path.home() / '.zero-player/signing'
    folder.mkdir(parents=True, exist_ok=True)
    key = folder / 'zero-player-release.jks'
    if key.exists():
        raise SystemExit('Existing release key found. Restore key.properties instead of overwriting the key.')
    keytool = shutil.which('keytool') or str(Path(os.environ['JAVA_HOME']) / 'bin/keytool.exe')
    password = secrets.token_urlsafe(40)
    result = subprocess.run([
        keytool, '-genkeypair', '-noprompt', '-storetype', 'JKS', '-keystore', str(key),
        '-alias', 'zero-player', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000',
        '-storepass:env', 'ZERO_PLAYER_STORE_PASSWORD', '-keypass:env', 'ZERO_PLAYER_STORE_PASSWORD',
        '-dname', 'CN=Zero Player, OU=Open Source, O=Zero Player',
    ], env={**os.environ, 'ZERO_PLAYER_STORE_PASSWORD': password}, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('keytool failed; no signing configuration written.')
    contents = ('storeFile=' + key.as_posix() + '\nstorePassword=' + password +
                '\nkeyAlias=zero-player\nkeyPassword=' + password + '\n')
    config.write_text(contents, encoding='utf-8')
    (folder / 'key.properties').write_text(contents, encoding='utf-8')
    print('Release key and recovery configuration created outside the repository:', folder)
    print('Back up this private folder securely; do not upload it.')


if __name__ == '__main__':
    main()
