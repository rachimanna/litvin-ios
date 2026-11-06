import importlib.util
import plistlib
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('make_esign_source', Path(__file__).parents[1] / 'make_esign_source.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


class ESignSourceTests(unittest.TestCase):
    def test_metadata_comes_from_main_application(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Litvin.ipa'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('Payload/Telegram.app/Info.plist', plistlib.dumps({'CFBundleIdentifier': 'app.test.litvin', 'CFBundleShortVersionString': '13.0', 'MinimumOSVersion': '15.0'}))
                archive.writestr('Payload/Telegram.app/PlugIns/Share.appex/Info.plist', plistlib.dumps({'CFBundleIdentifier': 'extension'}))
            app = source.make_source(path, 'rachimanna/litvin-ios', 'ios-build-1')['apps'][0]
            self.assertEqual(app['bundleIdentifier'], 'app.test.litvin')
            self.assertEqual(app['version'], '13.0')
            self.assertEqual(app['size'], path.stat().st_size)
            self.assertEqual(app['downloadURL'], 'https://github.com/rachimanna/litvin-ios/releases/download/ios-build-1/Litvin.ipa')

    def test_missing_application_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bad.ipa'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('README', 'not an app')
            with self.assertRaises(ValueError):
                source.make_source(path, 'rachimanna/litvin-ios', 'ios-build-1')

    def test_release_paths_are_validated(self):
        with self.assertRaises(ValueError):
            source.make_source(Path('unused'), 'owner/repo?token=x', 'build')


if __name__ == '__main__':
    unittest.main()
