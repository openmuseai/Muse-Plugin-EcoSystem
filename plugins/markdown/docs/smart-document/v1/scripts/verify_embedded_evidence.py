#!/usr/bin/env python3
"""Verify immutable P10 reference, child-domain and actual UI evidence."""
import argparse
import hashlib
import json
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',action='store_true');args=parser.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase10-embedded-20261106';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
manifest=read('manifest.json')
for item in manifest['files']:
    f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
    assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root))for f in root.rglob('*')if f.is_file()}-{'manifest.json'}=={i['path']for i in manifest['files']}
for platform in ['macos','ios','bridge_macos']:
    a=read(platform+'/embedded-e2e.json');b=read(platform+'/embedded-reopen.json');r=read(platform+'/result.json')
    assert r['status']=='passed-embedded-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(6,3)
    assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run'] and a['objectId']==b['objectId']
    assert a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
    for name in ['embedded_document_test.dart.log','embedded_reopen_test.dart.log']:
        log=(root/platform/name).read_text();assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
native=read('bridge_macos/embedded-e2e.json')
for name,count,unique in [('embedded-web-result.json',9,7),('embedded-web-reload.json',3,3),('embedded-native-web-readback.json',3,3)]:
    r=read(name);assert r['status']=='passed' and len(r['checks'])==count and len(set(r['checks']))==unique
    for key in ['objectId','datasetObjectId','rowId']:assert r[key]==native[key],(name,key)
for name in ['embed-document-local-qualified.log','embed-dataset-full-qualified.log','embed-pinned-session-tests.log',
             'embed-resource-tests.log','embed-contract-tests.log','embed-document-cloud-regression.log','embed-native-web-readback-qualified.log']:
    assert 'All tests passed!'in(root/name).read_text(),name
assert 'FAILED'in(root/'superseded-or-diagnostic/embed-first-cell-undo-before.log').read_text()
assert 'NativeAssetsDlopen'in(root/'superseded-or-diagnostic/embed-native-readback-sample.txt').read_text()
for item in read('source-lock.json')['files']:
    f=root/'source'/item['path'];assert f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
    if args.source:
        current=workspace/item['path'];assert current.is_file() and hashlib.sha256(current.read_bytes()).hexdigest()==item['sha256'],item['path']
r=read('result.json');assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and r['android']=='unrun' and not r['parityCases']
assert r['fullParityGate']=={'status':'rejected-expected','exitCode':1}
print(f'P10: {len(manifest["files"])} artifacts verified; original embedded database increment passed; full product NOT COMPLETE')
