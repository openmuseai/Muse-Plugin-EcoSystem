#!/usr/bin/env python3
"""Verify immutable P13 authority/lifetime regressions and actual application UI."""
import argparse
import hashlib
import json
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',action='store_true');args=parser.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase13-lifecycle-20261107';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
manifest=read('manifest.json')
for item in manifest['files']:
    f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
    assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root))for f in root.rglob('*')if f.is_file()}-{'manifest.json'}=={i['path']for i in manifest['files']}
for platform in ['macos','ios']:
    a=read(platform+'/lifecycle-e2e.json');b=read(platform+'/lifecycle-reopen.json');r=read(platform+'/result.json')
    assert r['status']=='passed-lifecycle-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(6,3)
    assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run']
    assert a['objectId']==b['objectId'] and a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
    assert a['target']['selector']['objectId']==a['datasetObjectId']
    assert a['views'][0]['rows'][0]['id']==a['rowId'] and a['views'][0]['rows'][0]['cells']['title']['value']=='恢复后的编辑'
    for name in ['lifecycle_document_test.dart.log','lifecycle_reopen_test.dart.log']:
        log=(root/platform/name).read_text();assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log
native=read('macos/lifecycle-e2e.json')
for name,count in [('lifecycle-web-result.json',8),('lifecycle-web-reload.json',4),('lifecycle-native-web-readback.json',4)]:
    r=read(name);assert r['status']=='passed' and len(r['checks'])==len(set(r['checks']))==count
    for key in ['objectId','datasetObjectId','rowId']:assert r[key]==native[key],(name,key)
for name,count in [('p13-document-local.log',38),('p13-dataset-local.log',33),('p13-dataset-sdk-tests.log',3),('p13-document-cloud.log',4)]:
    assert f'+{count}: All tests passed!'in(root/name).read_text(),name
assert '+0 -5: Some tests failed.'in(root/'p13-document-lifecycle-before.log').read_text()
assert '+0 -6: Some tests failed.'in(root/'p13-dataset-lifecycle-before.log').read_text()
assert 'All tests passed!'in(root/'p13-lifecycle-native-web-readback-final.log').read_text()
for name in ['p13-document-analysis.log','p13-dataset-analysis.log','p13-example-analysis-final.log',
             'p13-document-sdk-analysis.log','p13-dataset-sdk-analysis.log','p13-lifecycle-web-analysis-final.log']:
    assert 'No issues found!'in(root/name).read_text(),name
assert '子资源打开次数：1；已释放'in(root/'lifecycle-web-released.ax.txt').read_text()
assert '浏览器恢复后的编辑'in(root/'lifecycle-web-editor.ax.txt').read_text()
assert '文档已关闭，本机副本已保留'in(root/'lifecycle-web-closed.ax.txt').read_text()
assert '通过 8 项'in(root/'lifecycle-web-closed.ax.txt').read_text()
assert '通过 4 项'in(root/'lifecycle-web-reopen.ax.txt').read_text()
assert 'fresh-child-UI-edits-the-same-row-while-old-HTTP-response-remains-held'in(root/'diagnostic/manual-operation-exceeded-request-deadline.ax.txt').read_text()
for kind in ['row','root']:
    r=read('lifecycle-web-'+kind+'-timing.json')
    assert r['status']=='passed-observed-ui' and 0<r['milliseconds']<r['transportDeadlineMilliseconds']==20000
for item in read('source-lock.json')['files']:
    f=root/'source'/item['path'];assert f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
    if args.source:
        current=workspace/item['path'];assert current.is_file() and hashlib.sha256(current.read_bytes()).hexdigest()==item['sha256'],item['path']
r=read('result.json')
assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and not r['parityCases'] and r['android']=='unrun'
assert r['fullParityGate']=={'status':'rejected-expected','exitCode':1}
print(f'P13: {len(manifest["files"])} artifacts verified; lifecycle/authority increment passed; full product NOT COMPLETE')
