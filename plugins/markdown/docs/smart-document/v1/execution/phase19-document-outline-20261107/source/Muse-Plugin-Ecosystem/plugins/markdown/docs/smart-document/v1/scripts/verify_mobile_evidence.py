#!/usr/bin/env python3
"""Verify the archived Mobile receipts/artifacts; optionally compare current sources."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

p = argparse.ArgumentParser()
p.add_argument('--source', action='store_true')
args = p.parse_args()
docs = Path(__file__).resolve().parents[1]
root = docs / 'execution/phase3-mobile-20261105'
workspace = docs.parents[5]
manifest = json.loads((root / 'manifest.json').read_text())
errors = []
for item in manifest['files']:
    path = root / item['path']
    if not path.resolve().is_relative_to(root.resolve()) or path.is_symlink() or not path.is_file():
        errors.append('Invalid artifact: ' + item['path'])
        continue
    raw = path.read_bytes()
    if len(raw) != item['bytes'] or hashlib.sha256(raw).hexdigest() != item['sha256']:
        errors.append('Changed artifact: ' + item['path'])
actual = {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()} - {'manifest.json'}
if actual != {f['path'] for f in manifest['files']}:
    errors.append('Unlisted/missing artifact')
receipt = json.loads((root / 'ios-local-result.json').read_text())
if receipt['status'] != 'passed-local-slice' or len(receipt['checks']) != 2:
    errors.append('Invalid local slice receipt')
else:
    first, second = receipt['checks']
    if first['objectId'] != second['objectId'] or not first['softKeyboardVisible']:
        errors.append('Resource identity or actual soft keyboard was not verified')
result = json.loads((root / 'result.json').read_text())
if result['status'] != 'partial' or result['fullProductAcceptance'] != 'not-complete':
    errors.append('Do not turn this slice into full product acceptance')
if args.source:
    for item in json.loads((root / 'source-lock.json').read_text())['files']:
        file = workspace / item['path']
        if not file.resolve().is_relative_to(workspace) or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != item['sha256']:
            errors.append('Current source differs: ' + item['path'])
if errors:
    sys.exit('\n'.join(errors))
print(f"Mobile M3-A: {len(manifest['files'])} artifacts verified; iOS local/fresh process passed; Cloud/full acceptance remain incomplete")
