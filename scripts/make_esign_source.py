#!/usr/bin/env python3
"""Read the built IPA metadata and create an ESign/AltStore-style source."""
import argparse
import datetime
import hashlib
import json
import plistlib
import re
from pathlib import Path
from urllib.parse import quote
import zipfile


def make_source(ipa, repository, tag):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid GitHub repository')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', tag):
        raise ValueError('Invalid release tag')
    with zipfile.ZipFile(ipa) as archive:
        candidates = [info for info in archive.infolist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', info.filename)]
        if len(candidates) != 1 or candidates[0].file_size > 1024 * 1024:
            raise ValueError('IPA must contain exactly one main application Info.plist')
        info = plistlib.loads(archive.read(candidates[0]))
    bundle = info.get('CFBundleIdentifier')
    version = info.get('CFBundleShortVersionString')
    if not isinstance(bundle, str) or not bundle or not isinstance(version, str) or not version:
        raise ValueError('Missing application identifier or version')
    root = f'https://github.com/{repository}/releases/download/{quote(tag, safe="")}'
    app = {
        'name': 'Litvin',
        'bundleIdentifier': bundle,
        'developerName': repository.split('/')[0],
        'version': version,
        'versionDate': datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
        'versionDescription': 'Litvin iOS build. Sign with your own certificate in ESign before installing.',
        'downloadURL': root + '/Litvin.ipa',
        'iconURL': root + '/Litvin-icon.png',
        'size': ipa.stat().st_size,
        'minOSVersion': info.get('MinimumOSVersion', '15.0'),
        'localizedDescription': 'Unofficial Telegram client with local privacy tools. No AI.',
    }
    return {'name': 'Litvin', 'identifier': 'app.litvin.source', 'sourceURL': f'https://github.com/{repository}/releases/latest/download/esign-source.json', 'apps': [app], 'news': []}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = make_source(args.ipa, args.repository, args.tag)
    args.output.write_text(json.dumps(source, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    with args.ipa.open('rb') as file:
        digest = hashlib.file_digest(file, 'sha256').hexdigest()
    args.ipa.with_suffix('.ipa.sha256').write_text(f'{digest}  {args.ipa.name}\n', encoding='utf-8')


if __name__ == '__main__':
    main()
