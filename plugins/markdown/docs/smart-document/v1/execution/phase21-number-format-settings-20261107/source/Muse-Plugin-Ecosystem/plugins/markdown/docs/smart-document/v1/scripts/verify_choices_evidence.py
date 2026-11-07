#!/usr/bin/env python3
"""Verify immutable P9 field evidence without upgrading the full-feature gate."""
import argparse
import hashlib
import json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');args=p.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase9-choices-20261106';workspace=docs.parents[5]
manifest=json.loads((root/'manifest.json').read_text())
for item in manifest['files']:
    f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
    assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()}-{'manifest.json'}=={i['path'] for i in manifest['files']}
for platform in ['macos','ios']:
    report=json.loads((root/platform/'result.json').read_text());a=json.loads((root/platform/'choices-e2e.json').read_text());b=json.loads((root/platform/'choices-reopen.json').read_text())
    assert report['status']=='passed-choices-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(8,4)
    assert a['status']==b['status']=='passed' and a['objectId']==b['objectId'] and a['run']==b['run']==report['run']
    for name in ['choices_document_test.dart.log','choices_reopen_test.dart.log']:
        log=(root/platform/name).read_text();assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
records={}
for name,count in [('choices-web-result.json',7),('choices-web-reload.json',3),('choices-native-web-readback.json',5),('dataset-choice-cloud-result.json',5)]:
    value=json.loads((root/name).read_text());assert value['status']=='passed' and len(value['checks'])==count;records[name]=value
mac=json.loads((root/'macos/choices-e2e.json').read_text())
for name in ['choices-web-result.json','choices-web-reload.json','choices-native-web-readback.json']:
    assert records[name]['objectId']==mac['objectId'] and records[name]['rowId']==mac['rowId']
for name in ['dataset-choice-final-all-tests.log','dataset-choice-transport-tests.log','dataset-choice-document-cloud-regression.log','dataset-stale-http-after.log']:
    assert 'All tests passed!' in (root/name).read_text(),name
assert 'Connection closed before full header' in (root/'superseded-or-diagnostic/dataset-stale-http-before.log').read_text()
result=json.loads((root/'result.json').read_text());assert result['status']=='partial' and result['android']=='unrun' and result['fullProductAcceptance']=='not-complete' and not result['parityCases']
assert result['fullParityGate']=={'status':'rejected-expected','exitCode':1}
if args.source:
    for item in json.loads((root/'source-lock.json').read_text())['files']:
        f=workspace/item['path'];assert f.resolve().is_relative_to(workspace) and f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
print(f'P9: {len(manifest["files"])} artifacts verified; original choice-field/UI increment passed; full product NOT COMPLETE')
