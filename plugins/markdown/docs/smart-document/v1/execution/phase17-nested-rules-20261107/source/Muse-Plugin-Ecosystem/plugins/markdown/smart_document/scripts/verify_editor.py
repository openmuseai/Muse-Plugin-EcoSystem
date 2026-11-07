#!/usr/bin/env python3
"""Verify the pinned editor runtime subset and its explicit compatibility patches."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'vendor/appflowy_editor'
metadata = json.loads((root / 'openmuse-upstream.json').read_text())
expected = json.loads((root / 'upstream-files.json').read_text())
assert metadata['revision'] == '470c4e77c71b63f693ce0923a927afcd667d6f3b'
for patch in metadata['patches']:
    expected[patch['file']] = patch['sha256']
for name, digest in expected.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
assert hashlib.sha256((root / 'openmuse.patch').read_bytes()).hexdigest() == metadata['patchSha256']
print(f'Pinned editor: {len(expected)} runtime files verified; {len(metadata["patches"])} explicit patches')

collab = root.parent / 'appflowy_collab'
metadata = json.loads((collab / 'openmuse-upstream.json').read_text())
expected = json.loads((collab / 'upstream-files.json').read_text())
assert metadata['revision'] == 'e59260e524f33104b0ddcd6bb8f6218cad0f7e18'
for patch in metadata['patches']:
    expected[patch['file']] = patch['sha256']
for name, digest in expected.items():
    assert hashlib.sha256((collab / name).read_bytes()).hexdigest() == digest, name
assert hashlib.sha256((collab / 'openmuse.patch').read_bytes()).hexdigest() == metadata['patchSha256']
print(f'Pinned Collab: {len(expected)} runtime files verified; {len(metadata["patches"])} explicit patches')
