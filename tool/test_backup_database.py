import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('backup_database', Path(__file__).with_name('backup_database.py'))
backup_database = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup_database)


class BackupTest(unittest.TestCase):
    def test_success_and_existing_destination_preserved(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / '源 #.sqlite'
            output = Path(root) / 'backup.sqlite'
            db = sqlite3.connect(source)
            db.execute('CREATE TABLE sample(value)')
            db.execute('INSERT INTO sample VALUES(42)')
            db.commit()
            db.close()
            with patch('sys.argv', ['backup', str(source), str(output)]):
                backup_database.main()
                original = output.read_bytes()
                with self.assertRaises(SystemExit):
                    backup_database.main()
            self.assertEqual(output.read_bytes(), original)
            self.assertFalse(list(Path(root).glob('*.tmp')))

    def test_failure_leaves_no_published_or_temporary_backup(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / 'broken.sqlite'
            source.write_bytes(b'not a database')
            output = Path(root) / 'backup.sqlite'
            with patch('sys.argv', ['backup', str(source), str(output)]):
                with self.assertRaises(sqlite3.DatabaseError):
                    backup_database.main()
            self.assertFalse(output.exists())
            self.assertFalse(list(Path(root).glob('*.tmp')))


if __name__ == '__main__':
    unittest.main()
