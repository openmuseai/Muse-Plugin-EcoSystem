#!/usr/bin/env python3
"""Verify immutable P14 rule reuse, original object identities and actual UI."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');args=p.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase14-view-rules-20261107';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
m=read('manifest.json')
for item in m['files']:
 f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
 assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root))for f in root.rglob('*')if f.is_file()}-{'manifest.json'}=={i['path']for i in m['files']}
for platform in ['macos','ios']:
 a=read(platform+'/rules-e2e.json');b=read(platform+'/rules-reopen.json');r=read(platform+'/result.json')
 assert r['status']=='passed-rules-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(7,3)
 assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run']
 assert a['objectId']==b['objectId'] and a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
 assert a['target']['selector']['objectId']==a['datasetObjectId']
 v=a['views'][0];assert v['rulesReady'] and v['rows'][0]['id']==a['rowB'] and v['rows'][0]['cells']['title']['value']=='Muse Z'
 assert len(v['rowObjects'])==2 and v['filters'][0]['content']=='Muse' and v['sorts'][0]['condition']==1
 for name in ['view_rules_document_test.dart.log','view_rules_reopen_test.dart.log']:
  log=(root/platform/name).read_text();assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log
native=read('macos/rules-e2e.json')
for name,count in [('rules-web-result.json',9),('rules-web-peer.json',4),('rules-web-reload.json',4),('rules-native-web-readback.json',4)]:
 r=read(name);assert r['status']=='passed' and len(r['checks'])==len(set(r['checks']))==count
 for key in ['objectId','datasetObjectId','rowA','rowB']:assert r[key]==native[key],(name,key)
for name,count in [('p14-dataset-local-qualified.log',36),('p14-dataset-sdk-tests.log',3)]:assert f'+{count}: All tests passed!'in(root/name).read_text(),name
for name,count in [('p14-core-qualified.log',25),('p14-original-view-rules-tests-offline.log',14)]:assert f'test result: ok. {count} passed; 0 failed'in(root/name).read_text(),name
for name in ['p14-dataset-analysis-qualified.log','p14-dataset-sdk-analysis.log','p14-example-analysis-qualified.log','p14-view-rules-web-analysis-qualified.log']:assert 'No issues found!'in(root/name).read_text(),name
assert 'All tests passed!'in(root/'p14-native-web-readback-qualified.log').read_text()
assert 'View rules vendor: 12 pinned originals'in(root/'p14-view-rules-vendor.log').read_text()
assert '视图规则或字段已被修改'in(root/'rules-web-conflict.ax.txt').read_text()
assert 'zero-HTTP-content-requests-during-hidden-row-reentry'in(root/'rules-web-hidden.ax.txt').read_text()
assert '通过 9 项'in(root/'rules-web-editor.ax.txt').read_text()
assert '通过 4 项'in(root/'rules-web-reopen.ax.txt').read_text()
artifacts=read('dataset-wasm-artifacts.json')
for item in artifacts['artifacts']:
 f=root/'runtime-artifacts'/item['file'];assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
for item in read('source-lock.json')['files']:
 f=root/'source'/item['path'];assert f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
 if args.source:
  current=workspace/item['path'];assert current.is_file() and hashlib.sha256(current.read_bytes()).hexdigest()==item['sha256'],item['path']
r=read('result.json');assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and not r['parityCases'] and r['android']=='unrun'
assert r['fullParityGate']=={'status':'rejected-expected','exitCode':1}
print(f'P14: {len(m["files"])} artifacts verified; shared view increment passed; full product NOT COMPLETE')
