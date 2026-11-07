#!/usr/bin/env python3
"""Verify P4 evidence integrity and slice boundaries; optionally check current code."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--source', action='store_true')
args = parser.parse_args()
docs = Path(__file__).resolve().parents[1]
root = docs / 'execution/phase4-20261106'
workspace = docs.parents[5]
errors = []
manifest = json.loads((root / 'manifest.json').read_text())
for item in manifest['files']:
    path = root / item['path']
    if not path.resolve().is_relative_to(root.resolve()) or path.is_symlink() or not path.is_file():
        errors.append('Invalid artifact: ' + item['path'])
        continue
    raw = path.read_bytes()
    if len(raw) != item['bytes'] or hashlib.sha256(raw).hexdigest() != item['sha256']:
        errors.append('Changed artifact: ' + item['path'])
actual = {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()} - {'manifest.json'}
if actual != {item['path'] for item in manifest['files']}:
    errors.append('Unlisted/missing artifact')
result = json.loads((root / 'result.json').read_text())
if result['status'] != 'partial' or result['fullProductAcceptance'] != 'not-complete' or result.get('parityCases'):
    errors.append('P4 slice must not assert full parity acceptance')
mobile = json.loads((root / 'ios/result.json').read_text())
if mobile['status'] != 'passed-cloud-slice' or len(mobile['checks']) != 2:
    errors.append('Invalid Mobile Cloud slice')
else:
    primary, reopened = mobile['checks']
    if primary['objectId'] != reopened['objectId'] or primary['cloud'] != 'tested':
        errors.append('Mobile resource identity or Cloud receipt invalid')
    if len(primary['checks']) != 8 or len(reopened['checks']) != 3:
        errors.append('Missing Mobile code/Cloud/fresh-process checks')
mac = json.loads((root / 'macos/native-e2e.json').read_text())
web = json.loads((root / 'browser-regression/summary.json').read_text())
if mac['status'] != 'passed' or len(mac['checks']) != 8:
    errors.append('Missing final native UI menu checks')
if web['status'] != 'passed' or len(web['steps']) != 12 or (web['browserChecks'], web['reloadChecks'], web['nativeReadbackChecks']) != (7, 1, 3):
    errors.append('Invalid actual browser/native regression')
if result.get('fullParityGate') != {'status': 'rejected-expected', 'exitCode': 1}:
    errors.append('Incomplete product must fail the full parity gate')
if args.source:
    for item in json.loads((root / 'source-lock.json').read_text())['files']:
        file = workspace / item['path']
        if not file.resolve().is_relative_to(workspace) or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != item['sha256']:
            errors.append('Current source differs: ' + item['path'])
if errors:
    sys.exit('\n'.join(errors))
print(f"P4: {len(manifest['files'])} artifacts verified; macOS/Web/iOS Cloud slices passed; full parity NOT COMPLETE")
