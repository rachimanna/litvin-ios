#!/usr/bin/env python3
"""Renew Telegram's self-signed CI profiles; never use for Apple-issued profiles."""
import datetime
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path


def refresh_profile(path, identity, now):
    decoded = subprocess.check_output(['security', 'cms', '-D', '-i', str(path)])
    profile = plistlib.loads(decoded)
    if profile['ExpirationDate'] > now + datetime.timedelta(days=30):
        return False

    profile['CreationDate'] = now
    profile['ExpirationDate'] = now + datetime.timedelta(days=365)
    # The old DER payload describes the old dates. The CMS signature is recreated
    # below using the same public, self-signed test identity as upstream.
    profile.pop('DER-Encoded-Profile', None)
    with tempfile.TemporaryDirectory(dir=path.parent) as directory:
        payload = Path(directory) / 'profile.plist'
        signed = Path(directory) / 'profile.mobileprovision'
        payload.write_bytes(plistlib.dumps(profile))
        subprocess.run([
            'security', 'cms', '-S', '-k', 'temp.keychain', '-N', identity,
            '-i', str(payload), '-o', str(signed),
        ], check=True)
        verified = plistlib.loads(subprocess.check_output([
            'security', 'cms', '-D', '-i', str(signed),
        ]))
        if verified != profile:
            raise RuntimeError(f'Resigned profile verification failed: {path.name}')
        signed.replace(path)
    return True


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: refresh_fake_profiles.py <telegram-ios-root>')
    root = Path(sys.argv[1]).resolve()
    # Deliberately restricted to upstream's fake signing assets.
    signing = root / 'build-system/fake-codesigning'
    sys.path.insert(0, str(root / 'build-system/Make'))
    from GenerateProfiles import get_signing_identity_from_p12
    identity = get_signing_identity_from_p12(str(signing / 'certs/SelfSigned.p12'))
    if not identity:
        raise SystemExit('Could not resolve the upstream self-signed test identity')
    paths = sorted((signing / 'profiles').glob('*.mobileprovision'))
    if not paths:
        raise SystemExit('No upstream fake provisioning profiles found')
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None, microsecond=0)
    for path in paths:
        changed = refresh_profile(path, identity, now)
        print(f'{path.name}: {"renewed for CI" if changed else "still valid"}')


if __name__ == '__main__':
    main()
