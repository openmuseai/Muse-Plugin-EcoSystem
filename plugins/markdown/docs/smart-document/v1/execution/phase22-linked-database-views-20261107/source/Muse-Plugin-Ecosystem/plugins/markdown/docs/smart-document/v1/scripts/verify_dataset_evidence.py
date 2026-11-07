#!/usr/bin/env python3
"""Verify immutable P7 evidence without upgrading partial features to parity."""
import argparse
import hashlib
import json
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',action='store_true')
args=parser.parse_args()
docs=Path(__file__).resolve().parents[1]
root=docs/'execution/phase7-dataset-20261106'
workspace=docs.parents[5]
manifest=json.loads((root/'manifest.json').read_text())
for item in manifest['files']:
    path=root/item['path']
    assert path.resolve().is_relative_to(root.resolve()) and path.is_file() and not path.is_symlink()
    assert path.stat().st_size==item['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}-{'manifest.json'}=={p['path'] for p in manifest['files']}
for platform in ['macos','ios']:
    report=json.loads((root/platform/'result.json').read_text())
    primary=json.loads((root/platform/'dataset-e2e.json').read_text())
    reopened=json.loads((root/platform/'dataset-reopen.json').read_text())
    assert report['status']=='passed-dataset-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(6,4)
    assert primary['objectId']==reopened['objectId'] and primary['run']==reopened['run']==report['run']
    assert primary['status']==reopened['status']=='passed'
    for name in ['dataset_document_test.dart.log','dataset_reopen_test.dart.log']:
        log=(root/platform/name).read_text()
        assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
for name,count in [('dataset-web-result.json',8),('dataset-web-reload.json',3),('dataset-cloud-result.json',6),('dataset-cloud-deletion-result.json',7),('document-cloud-deletion-result.json',5)]:
    report=json.loads((root/name).read_text());assert report['status'].startswith('passed') and len(report['checks'])==count
assert json.loads((root/'dataset-web-result.json').read_text())['objectId']==json.loads((root/'dataset-web-reload.json').read_text())['objectId']
regression=json.loads((root/'document-regression/summary.json').read_text())
assert regression['status']=='passed' and (regression['browserChecks'],regression['reloadChecks'],regression['nativeReadbackChecks'])==(10,3,6)
result=json.loads((root/'result.json').read_text())
assert result['status']=='partial' and result['fullProductAcceptance']=='not-complete' and result['android']=='unrun' and not result['parityCases']
assert result['fullParityGate']=={'status':'rejected-expected','exitCode':1}
assert 'registered_object_scope_type_and_tombstone_override_cached_state ... ok' in (root/'dataset-cloud-lifecycle-tests.log').read_text()
if args.source:
    for item in json.loads((root/'source-lock.json').read_text())['files']:
        path=workspace/item['path']
        assert path.resolve().is_relative_to(workspace) and path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],item['path']
print(f'P7: {len(manifest["files"])} artifacts verified; independent Dataset and lifecycle increments passed; full product NOT COMPLETE')
