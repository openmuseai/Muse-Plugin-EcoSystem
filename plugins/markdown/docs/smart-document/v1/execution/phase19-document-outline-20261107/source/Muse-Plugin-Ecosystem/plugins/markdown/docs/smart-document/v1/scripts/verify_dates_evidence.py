#!/usr/bin/env python3
"""Verify immutable P12 original-date/core, contextual keyboard and UI evidence."""
import argparse
import hashlib
import json
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',action='store_true');args=parser.parse_args()
docs=Path(__file__).resolve().parents[1]
root=docs/'execution/phase12-dates-20261106';workspace=docs.parents[5]
def read(name): return json.loads((root/name).read_text())
manifest=read('manifest.json')
for item in manifest['files']:
    f=root/item['path']
    assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
    assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root))for f in root.rglob('*')if f.is_file()}-{'manifest.json'}=={i['path']for i in manifest['files']}
for platform in ['macos','ios','bridge_macos']:
    a=read(platform+'/dates-e2e.json');b=read(platform+'/dates-reopen.json');r=read(platform+'/result.json')
    assert r['status']=='passed-dates-slice' and (r['primaryChecks'],r['freshProcessChecks'])==((6 if platform=='bridge_macos' else 7),3)
    assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run']
    assert a['objectId']==b['objectId'] and a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
    assert a['target']['selector']['objectId']==a['datasetObjectId']
    field=next(f for f in a['views'][0]['columns']if f['id']==a['fieldId'])
    assert field['storageType']==2 and field['dateOptions']['timezone']=='America/New_York'
    cell=next(row for row in a['views'][0]['rows']if row['id']==a['rowId'])['cells'][a['fieldId']]
    assert cell['value']=={'start':'2026-11-11T20:30:45-05:00','end':'2026-11-12T21:45:12-05:00',
      'includeTime':True,'isRange':True,'timezone':'America/New_York'}
    for name in ['dates_document_test.dart.log','dates_reopen_test.dart.log']:
        log=(root/platform/name).read_text()
        assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log,name
native=read('bridge_macos/dates-e2e.json')
for name,count in [('dates-web-result.json',9),('dates-web-peer.json',7),('dates-web-reload.json',5),('dates-native-web-readback.json',4)]:
    r=read(name);assert r['status']=='passed' and len(r['checks'])==len(set(r['checks']))==count
    for key in ['objectId','datasetObjectId','rowId','fieldId']:assert r[key]==native[key],(name,key)
for name,count in [('p12-dataset-local-final.log',25),('p12-document-local.log',32),('p12-dataset-sdk-tests.log',3)]:
    log=(root/name).read_text();assert f'+{count}: All tests passed!'in log,name
for name in ['p12-native-keyboard-2.log','p12-dates-interaction-final.log','p12-dates-native-web-readback.log']:
    assert 'All tests passed!'in(root/name).read_text(),name
assert '14 passed; 0 failed'in(root/'p12-date-rust-tests-final.log').read_text()
for name in ['p12-document-analysis.log','p12-dataset-analysis-final.log','p12-example-analysis-final.log',
             'p12-dataset-sdk-analysis.log','p12-dates-web-analysis-final.log']:
    assert 'No issues found!'in(root/name).read_text(),name
ax=(root/'dates-web-conflict.ax.txt').read_text()
assert '2026-11-14T10:00:00-05:00'in ax and '内容已被修改，草稿保留'in ax
assert '2026-11-16 11:22:33-05:00'in(root/'dates-web-keyboard-undo.ax.txt').read_text()
assert '2026-11-18 09:10:11-05:00'in(root/'dates-web-keyboard-redo.ax.txt').read_text()
for item in read('dataset-wasm-artifacts.json')['artifacts']:
    f=root/'runtime-artifacts'/item['file'];assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
for item in read('source-lock.json')['files']:
    f=root/'source'/item['path'];assert f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
    if args.source:
        current=workspace/item['path'];assert current.is_file() and hashlib.sha256(current.read_bytes()).hexdigest()==item['sha256'],item['path']
r=read('result.json')
assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and r['android']=='unrun' and not r['parityCases']
assert r['fullParityGate']=={'status':'rejected-expected','exitCode':1}
print(f'P12: {len(manifest["files"])} artifacts verified; dates/contextual-history increment passed; full product NOT COMPLETE')
