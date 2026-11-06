import datetime
import importlib.util
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('refresh_fake_profiles', Path(__file__).parents[1] / 'refresh_fake_profiles.py')
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


class RefreshFakeProfilesTests(unittest.TestCase):
    now = datetime.datetime(2026, 11, 6)

    def profile(self, expiration):
        return {
            'CreationDate': datetime.datetime(2025, 10, 30),
            'ExpirationDate': expiration,
            'Entitlements': {'application-identifier': 'C67CF9S4VU.ph.telegra.Telegraph.Share'},
            'DeveloperCertificates': [b'test-certificate'],
            'UUID': 'test-profile-id',
            'DER-Encoded-Profile': b'obsolete-dates',
        }

    def test_expired_profile_is_renewed_and_resigned(self):
        original = self.profile(datetime.datetime(2026, 10, 30))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Share.mobileprovision'
            path.write_bytes(b'original-cms')
            renewed = {}

            def sign(command, check):
                self.assertTrue(check)
                self.assertEqual(command[:7], ['security', 'cms', '-S', '-k', 'temp.keychain', '-N', 'SelfSigned'])
                renewed.update(plistlib.loads(Path(command[8]).read_bytes()))
                Path(command[10]).write_bytes(b'resigned-cms')

            def decode(command):
                return plistlib.dumps(original if command[-1] == str(path) else renewed)

            with patch.object(refresh.subprocess, 'check_output', side_effect=decode), patch.object(refresh.subprocess, 'run', side_effect=sign):
                self.assertTrue(refresh.refresh_profile(path, 'SelfSigned', self.now))
            self.assertEqual(path.read_bytes(), b'resigned-cms')
            self.assertEqual(renewed['ExpirationDate'], self.now + datetime.timedelta(days=365))
            self.assertEqual(renewed['CreationDate'], self.now)
            for key in ('Entitlements', 'DeveloperCertificates', 'UUID'):
                self.assertEqual(renewed[key], original[key])
            self.assertNotIn('DER-Encoded-Profile', renewed)

    def test_valid_profile_is_untouched(self):
        profile = self.profile(self.now + datetime.timedelta(days=90))
        with patch.object(refresh.subprocess, 'check_output', return_value=plistlib.dumps(profile)), patch.object(refresh.subprocess, 'run') as sign:
            self.assertFalse(refresh.refresh_profile(Path('valid.mobileprovision'), 'SelfSigned', self.now))
            sign.assert_not_called()

    def test_signing_failure_preserves_original_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Share.mobileprovision'
            path.write_bytes(b'original-cms')
            profile = self.profile(datetime.datetime(2026, 10, 30))
            with patch.object(refresh.subprocess, 'check_output', return_value=plistlib.dumps(profile)), patch.object(refresh.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'security')):
                with self.assertRaises(subprocess.CalledProcessError):
                    refresh.refresh_profile(path, 'SelfSigned', self.now)
            self.assertEqual(path.read_bytes(), b'original-cms')


if __name__ == '__main__':
    unittest.main()
