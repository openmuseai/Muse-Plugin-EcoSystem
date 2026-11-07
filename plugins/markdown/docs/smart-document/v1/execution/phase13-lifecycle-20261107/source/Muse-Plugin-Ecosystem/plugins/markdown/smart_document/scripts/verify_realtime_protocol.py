#!/usr/bin/env python3
"""Verify the pinned original AppFlowy wire source and controlled adaptations."""
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'vendor/appflowy_proto'
m = json.loads((root / 'openmuse-upstream.json').read_text())
expected = json.loads((root / 'upstream-files.json').read_text())
assert m['revision'] == '5b44ac485f6dc1a17bb7366027c300aa87868e59'
assert m['collabRevision'] == 'e59260e524f33104b0ddcd6bb8f6218cad0f7e18'
for patch in m['patches']:
    assert patch['file'] in expected
    expected[patch['file']] = patch['sha256']
for name, digest in expected.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
assert hashlib.sha256((root / 'openmuse.patch').read_bytes()).hexdigest() == m['patchSha256']
assert 'build = false' in (root / 'Cargo.toml').read_text()
print(f'Original AppFlowy protocol: {len(expected)} files; {len(m["patches"])} controlled adaptations verified')
