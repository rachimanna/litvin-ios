#!/usr/bin/env python3
"""Verify presentation patches against the current pinned Telegram release."""
import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def main():
    repository = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('appearance_patch', repository / 'scripts/appearance_patch.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    original = module.patch
    targets = set()
    module.patch = lambda root, path, transform: targets.add(path)
    module.apply(Path('.'))
    module.patch = original
    ref = (repository / 'UPSTREAM_REF').read_text().strip()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        def download(target):
            destination = root / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['curl', '-fsSL', '--retry', '3', f'https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/{ref}/{target}', '-o', str(destination)], check=True)
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(download, sorted(targets)))
        module.apply(root)
        hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in targets}
        module.apply(root)
        assert hashes == {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in targets}, 'Non-idempotent appearance patch'
        if output := (os.environ.get('LITVIN_APPEARANCE_FIXTURE') or (sys.argv[1] if len(sys.argv) > 1 else None)):
            shutil.copytree(root, output, dirs_exist_ok=True)
        print(f'PASS: {len(targets)} appearance targets on {ref}; second application unchanged')


if __name__ == '__main__':
    main()
