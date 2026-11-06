#!/usr/bin/env python3
"""Check every feature edit against the exact pinned upstream and test reapplication."""
import hashlib
import importlib.util
import os
import shutil
import subprocess
import tempfile
import sys
from pathlib import Path


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    repository = Path(__file__).resolve().parents[1]
    features = load(repository / 'scripts/feature_patches.py')
    original_patch = features.patch
    targets = set()
    features.patch = lambda root, path, transform: targets.add(path)
    features.apply(Path('.'))
    features.patch = original_patch
    prefix = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen'
    targets.update([prefix + '/BUILD'] + [prefix + '/Sources/' + name + '.swift' for name in ['PeerInfoScreen', 'PeerInfoSettingsItems', 'PeerInfoScreenSettingsActions']])
    ref = (repository / 'UPSTREAM_REF').read_text().strip()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        for target in sorted(targets):
            destination = root / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            url = f'https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/{ref}/{target}'
            subprocess.run(['curl', '-fsSL', '--retry', '3', url, '-o', str(destination)], check=True)
        for script in ('litvin_patch.py', 'feature_patches.py'):
            subprocess.run([sys.executable, str(repository / 'scripts' / script), str(root)], check=True)
        before = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in targets}
        for script in ('litvin_patch.py', 'feature_patches.py'):
            subprocess.run([sys.executable, str(repository / 'scripts' / script), str(root)], check=True)
        after = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in targets}
        assert before == after, 'Integration is not idempotent'
        if output := os.environ.get('LITVIN_VERIFY_EXPORT'):
            shutil.copytree(root, output, dirs_exist_ok=True)
        print(f'PASS: all {len(targets)} upstream files patched and reapplication is unchanged')


if __name__ == '__main__':
    main()
