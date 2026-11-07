#!/usr/bin/env python3
"""Verify the P5-A table slice; it cannot certify full editing/collaboration parity."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', action='store_true')
args = parser.parse_args()
docs = Path(__file__).resolve().parents[1]
root = docs / 'execution/phase5-table-20261106'
workspace = docs.parents[5]
errors = []
manifest = json.loads((root / 'manifest.json').read_text())
for item in manifest['files']:
    file = root / item['path']
    if not file.resolve().is_relative_to(root.resolve()) or file.is_symlink() or not file.is_file():
        errors.append('Invalid artifact: ' + item['path']); continue
    raw = file.read_bytes()
    if len(raw) != item['bytes'] or hashlib.sha256(raw).hexdigest() != item['sha256']:
        errors.append('Changed artifact: ' + item['path'])
actual = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()} - {'manifest.json'}
if actual != {item['path'] for item in manifest['files']}:
    errors.append('Unlisted/missing artifact')
for platform in ['macos', 'ios']:
    result = json.loads((root / platform / 'result.json').read_text())
    a = json.loads((root / platform / 'table-e2e.json').read_text())
    b = json.loads((root / platform / 'table-reopen.json').read_text())
    if result['status'] != 'passed-table-slice' or result['primaryChecks'] != 6 or result['freshProcessChecks'] != 4:
        errors.append('Invalid table slice: ' + platform)
    if a['status'] != 'passed' or b['status'] != 'passed' or a['run'] != b['run'] or a['objectId'] != b['objectId']:
        errors.append('Different resource/run on reopen: ' + platform)
    if 'fresh-process-no-cloud-provider-or-credentials' not in b['checks']:
        errors.append('No credential-free reopen: ' + platform)
    log = (root / platform / 'table_document_test.dart.log').read_text()
    if 'All tests passed!' not in log or 'Warning: A call to tap()' in log:
        errors.append('UI test or physical hit test failed: ' + platform)
web = json.loads((root / 'web-regression/summary.json').read_text())
if web['status'] != 'passed' or (web['browserChecks'], web['reloadChecks'], web['nativeReadbackChecks']) != (8, 2, 4):
    errors.append('Missing actual Web/native table regression')
result = json.loads((root / 'result.json').read_text())
if result['status'] != 'partial' or result['fullProductAcceptance'] != 'not-complete' or result.get('parityCases') or result['android'] != 'unrun':
    errors.append('This fixed-grid slice must not claim full product/Android acceptance')
if result.get('fullParityGate') != {'status': 'rejected-expected', 'exitCode': 1}:
    errors.append('Incomplete full parity must fail the completion gate')
if args.source:
    for item in json.loads((root / 'source-lock.json').read_text())['files']:
        file = workspace / item['path']
        if not file.resolve().is_relative_to(workspace) or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != item['sha256']:
            errors.append('Current source differs: ' + item['path'])
if errors: sys.exit('\n'.join(errors))
print(f"P5-A: {len(manifest['files'])} artifacts verified; fixed-grid macOS/iOS/Web collaboration slices passed; full parity NOT COMPLETE")
