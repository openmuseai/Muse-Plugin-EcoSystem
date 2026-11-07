#!/usr/bin/env python3
"""Verify P11 actual root/row realtime, Guest boundaries and UI evidence."""
import argparse
import hashlib
import json
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',action='store_true');args=parser.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase11-dataset-realtime-20261106';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
manifest=read('manifest.json')
for item in manifest['files']:
    f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
    assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root))for f in root.rglob('*')if f.is_file()}-{'manifest.json'}=={i['path']for i in manifest['files']}
for platform in ['macos','ios','bridge_macos']:
    a=read(platform+'/dataset_realtime-e2e.json');b=read(platform+'/dataset_realtime-reopen.json');r=read(platform+'/result.json')
    assert r['status']=='passed-dataset_realtime-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(8,3)
    assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run']
    assert a['objectId']==b['objectId'] and a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
    for name in ['dataset_realtime_document_test.dart.log','dataset_realtime_reopen_test.dart.log']:
        log=(root/platform/name).read_text();assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log
native=read('bridge_macos/dataset_realtime-e2e.json');web=read('dataset-realtime-web-result.json')
for name,count in [('dataset-realtime-web-result.json',9),('dataset-realtime-web-peer.json',7),('dataset-realtime-web-reload.json',5),('dataset-realtime-native-web-readback.json',4)]:
    r=read(name);assert r['status']=='passed' and len(r['checks'])==len(set(r['checks']))==count
    for key in ['objectId','datasetObjectId','rowId']:assert r[key]==native[key],(name,key)
    assert r['newRowId']==web['newRowId'] and r['newRowId']not in {native['rowId'],native['newRowId']}
for name,count in [('dataset-realtime-cloud-result.json',6),('dataset-realtime-permissions-result.json',7)]:
    r=read(name);assert r['status']=='passed' and len(set(r['checks']))==count
for name in ['dataset-realtime-document-regression.log','dataset-realtime-full-regression.log','dataset-realtime-sdk-tests.log',
             'dataset-realtime-shared-widgets-tests.log','dataset-realtime-original-document-cloud.log','dataset-realtime-native-web-readback.log']:
    assert 'All tests passed!'in(root/name).read_text(),name
ax=(root/'dataset-realtime-web-conflict.ax.txt').read_text()
assert '未提交的网页草稿'in ax and '内容已被修改，请取消后重新编辑'in ax
assert '实时连接正常 · 接收确认暂不可用'in(root/'dataset-realtime-web-status.ax.txt').read_text()
assert 'modified during the build'in(root/'superseded-or-diagnostic/concurrent-generated-swift-package/dataset_realtime_document_test.dart.log').read_text()
for item in read('source-lock.json')['files']:
    f=root/'source'/item['path'];assert f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
    if args.source:
        current=workspace/item['path'];assert current.is_file() and hashlib.sha256(current.read_bytes()).hexdigest()==item['sha256'],item['path']
r=read('result.json');assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and r['android']=='unrun' and not r['parityCases']
assert r['fullParityGate']=={'status':'rejected-expected','exitCode':1}
print(f'P11: {len(manifest["files"])} artifacts verified; original dataset realtime/UI increment passed; full product NOT COMPLETE')
