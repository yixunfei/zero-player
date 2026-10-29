import unittest
from android_package_version import check_badging


class AndroidVersionTest(unittest.TestCase):
    def test_current_version_passes(self):
        check_badging("package: name='dev.zeroplayer.zero_player' versionCode='7' versionName='0.0.7' platformBuildVersionName=''", '0.0.7', 7)

    def test_stale_build_and_different_app_are_rejected(self):
        for text in [
            "package: name='dev.zeroplayer.zero_player' versionCode='6' versionName='0.0.7'",
            "package: name='dev.zeroplayer.zero_player' versionCode='7' versionName='0.0.6'",
            "package: name='wrong.app' versionCode='7' versionName='0.0.7'",
            'malformed output',
        ]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                check_badging(text, '0.0.7', 7)


if __name__ == '__main__':
    unittest.main()
