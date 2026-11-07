#!/usr/bin/env python3
"""Check all runtime source anchors, including the pinned tgcalls submodule."""
import importlib.util
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def main():
    repository = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('runtime_patch', repository / 'scripts/litvin_patch.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    edits = []
    module.edit = lambda root, path, transform: edits.append((path, transform))
    for name in ('install_icon_composer', 'install_alt_icons', 'allow_postbox', 'write_custom_logo_swift'):
        setattr(module, name, lambda root: None)
    ref = (repository / 'UPSTREAM_REF').read_text().strip()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        sys.argv = ['litvin_patch.py', str(root)]
        module.main()
        targets = sorted({path for path, _ in edits})
        # Git tree entry in Telegram's immutable release-13.0.0.
        tgcalls_ref = 'a024eaabf13c189d9577a14fb244bd242825ac96'
        def download(path):
            prefix = 'submodules/TgVoipWebrtc/tgcalls/'
            url = (f'https://raw.githubusercontent.com/TelegramMessenger/tgcalls/{tgcalls_ref}/{path[len(prefix):]}' if path.startswith(prefix)
                   else f'https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/{ref}/{path}')
            destination = root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['curl', '-fsSL', '--retry', '3', url, '-o', str(destination)], check=True)
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(download, targets))
        def apply():
            for path, transform in edits:
                file = root / path
                file.write_text(transform(file.read_text(encoding='utf-8'), path), encoding='utf-8')
        apply()
        before = {path: (root / path).read_bytes() for path in targets}
        apply()
        assert before == {path: (root / path).read_bytes() for path in targets}, 'Runtime patch is not idempotent'
        print(f'PASS: {len(targets)} runtime files on {ref}; reapplication unchanged')


if __name__ == '__main__':
    main()
