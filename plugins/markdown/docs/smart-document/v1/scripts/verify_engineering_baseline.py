#!/usr/bin/env python3
"""Read-only verification of the first-stage engineering input archive."""
import hashlib
import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1] / 'baselines/sd-f1-20261105'
    manifest = json.loads((root / 'manifest.json').read_text())
    assert manifest['baselineId'] == 'SD-F1-20261105'
    assert manifest['productBaselineId'] == 'SD-BL-1.2-20261105'
    expected = {'manifest.json'}
    for entry in manifest['files']:
        name = entry['path']
        path = root / name
        assert name not in expected, name
        assert path.resolve().is_relative_to(root.resolve()), name
        assert not path.is_symlink(), name
        data = path.read_bytes()
        assert len(data) == entry['bytes'], name
        assert hashlib.sha256(data).hexdigest() == entry['sha256'], name
        expected.add(name)
    actual = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}
    assert actual == expected, actual ^ expected
    print(f'SD-F1-20261105: {len(expected) - 1} engineering input files verified')


if __name__ == '__main__':
    main()
