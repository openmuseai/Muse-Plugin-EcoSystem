#!/usr/bin/env python3
"""Read-only hash verification of the additive Mobile implementation input."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1] / 'baselines/sd-mob-v1.3-20261105'
manifest = json.loads((root / 'manifest.json').read_text())
errors = []
listed = set()
for entry in manifest['files']:
    path = root / entry['path']
    listed.add(entry['path'])
    if not path.resolve().is_relative_to(root.resolve()) or path.is_symlink() or not path.is_file():
        errors.append('Invalid file: ' + entry['path'])
        continue
    data = path.read_bytes()
    if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
        errors.append('Content changed: ' + entry['path'])
actual = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()} - {'manifest.json'}
if actual != listed:
    errors.append('Unlisted or missing files')
qa = json.loads((root / 'mobile-functional-review/design-qa.json').read_text())
if len(qa['frames']) != 20 or any(f['overflow'] for f in qa['frames']):
    errors.append('Invalid frame QA coverage')
if [r['width'] for r in qa['responsive']] != [320, 360, 390, 430] or any(r['scrollWidth'] != r['width'] for r in qa['responsive']):
    errors.append('Invalid responsive QA coverage')
if errors:
    sys.exit('\n'.join(errors))
print(f"{manifest['baselineId']}: {len(listed)} files verified; 20 design frames / 4 widths; product verification is separate")
