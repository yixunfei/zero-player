"""Exercise release archives against real, isolated Git indexes."""
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import package_source


class PackageSourceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='source-archive-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git('init', '--quiet')
        self.write('pubspec.yaml', 'version: 1.2.3+4\n')
        self.write('lib/main.dart', 'reviewed content\n')
        self.git('add', '.')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def archive(self):
        with patch.object(package_source, 'ROOT', self.root):
            with contextlib.redirect_stdout(io.StringIO()):
                package_source.main()
        return self.root / 'artifacts/release/1.2.3/zero-player-1.2.3-source.zip'

    def test_unstaged_edits_and_untracked_files_do_not_enter_archive(self):
        staged = self.git('show', ':lib/main.dart')
        self.write('lib/main.dart', 'unreviewed changes\n')
        self.write('private.txt', 'local data\n')
        with ZipFile(self.archive()) as archive:
            self.assertEqual(archive.read('lib/main.dart'), staged)
            self.assertNotIn('private.txt', archive.namelist())

    def test_version_is_read_from_the_same_staged_snapshot(self):
        self.write('pubspec.yaml', 'version: 9.9.9+99\n')
        with ZipFile(self.archive()) as archive:
            self.assertEqual(archive.read('pubspec.yaml'), self.git('show', ':pubspec.yaml'))

    def test_worktree_deletion_keeps_staged_file_in_archive(self):
        (self.root / 'lib/main.dart').unlink()
        with ZipFile(self.archive()) as archive:
            self.assertEqual(archive.read('lib/main.dart'), self.git('show', ':lib/main.dart'))

    def test_staged_signing_key_is_rejected(self):
        self.write('android/signing.jks', 'not a real key')
        self.git('add', '.')
        with self.assertRaises(SystemExit):
            self.archive()


if __name__ == '__main__':
    unittest.main()
