#!/usr/bin/env python3
"""Verify immutable P15 concurrent original-node and bounded-undo evidence."""
import argparse,hashlib,json,re
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');args=p.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase15-concurrent-views-20261107';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
m=read('manifest.json')
for item in m['files']:
 f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
 assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root))for f in root.rglob('*')if f.is_file()}-{'manifest.json'}=={i['path']for i in m['files']}
for platform in ['macos','ios']:
 a=read(platform+'/concurrent-e2e.json');b=read(platform+'/concurrent-reopen.json');r=read(platform+'/result.json')
 assert r['status']=='passed-concurrent-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(7,3)
 assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run']
 assert a['objectId']==b['objectId'] and a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
 assert a['target']['selector']['objectId']==a['datasetObjectId']
 v=a['views'][0];assert v['rulesReady'] and v['rows'][0]['id']==a['rowB'] and v['rows'][0]['cells']['title']['value']=='Muse Z'
 assert len(v['rowObjects'])==2 and v['filters'][0]['content']=='Muse' and v['sorts'][0]['condition']==1
 split=a['splitBeforePublish'];assert split['alice']=='Muse A' and split['bob']=='Muse B' and all(split['heldOriginalFrames'][who]>0 for who in ['alice','bob'])
 for name in ['concurrent_view_document_test.dart.log','concurrent_view_reopen_test.dart.log']:
  log=(root/platform/name).read_text();assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log
native=read('macos/concurrent-e2e.json')
for name,count in [('concurrent-web-result.json',10),('concurrent-web-peer.json',8),('concurrent-web-reload.json',5),('concurrent-native-web-readback.json',4)]:
 r=read(name);assert r['status']=='passed' and len(r['checks'])==len(set(r['checks']))==count
 for key in ['objectId','datasetObjectId','rowA','rowB']:assert r[key]==native[key],(name,key)
a=read('concurrent-web-result.json');b=read('concurrent-web-peer.json')
assert a['branch0']=='Muse A' and b['branch0']=='Muse Z' and a['merge0']==b['merge0'] and a['merge0']in {'Muse A','Muse Z'}
assert a['branch1']=='Muse A/1' and b['branch1']=='Muse/0' and a['merge1']==b['merge1']=={'filter':'Muse A','direction':0}
assert a['obsolete'] is True
for name,count in [('p15-dataset-local-final.log',38),('p15-dataset-sdk-tests.log',3),('p15-realtime-package-tests.log',2)]:assert f'+{count}: All tests passed!'in(root/name).read_text(),name
for name,count in [('p15-core-final.log',34),('p15-original-yrs-undo-cmake.log',19)]:assert f'test result: ok. {count} passed; 0 failed'in(root/name).read_text(),name
for name in ['p15-dataset-analysis-final.log','p15-dataset-sdk-analysis.log','p15-example-analysis-qualified.log','p15-concurrent-web-analysis-qualified.log','p15-realtime-package-analysis.log','p15-test-support-analysis.log']:assert 'No issues found!'in(root/name).read_text(),name
assert 'All tests passed!'in(root/'p15-native-web-readback.log').read_text()
assert '64 pinned original files'in(root/'p15-yrs-vendor.log').read_text()
assert '2 failed'in(root/'diagnostic/original-array-replacement-two-failures.log').read_text()
assert '1 failed'in(root/'diagnostic/original-undo-falls-through-one-failure.log').read_text()
for name,value in [('concurrent-web-alice-split.ax.txt','实际筛选：Muse A；实际排序：1'),('concurrent-web-bob-split.ax.txt','实际筛选：Muse Z；实际排序：1'),('concurrent-web-independent-split.ax.txt','实际筛选：Muse；实际排序：0'),('concurrent-web-independent-merged.ax.txt','实际筛选：Muse A；实际排序：0')]:assert value in(root/name).read_text()
assert '这条修改已被协作者覆盖，当前内容已保留'in(root/'concurrent-web-obsolete-toast.ax.txt').read_text()
assert re.search(r'\d+ button 撤销(?: 撤销)?,', (root/'concurrent-web-obsolete-undo.ax.txt').read_text())
assert '通过 10 项'in(root/'concurrent-web-editor.ax.txt').read_text()
assert '通过 5 项'in(root/'concurrent-web-reopen.ax.txt').read_text()
for item in read('dataset-wasm-artifacts.json')['artifacts']:
 f=root/'runtime-artifacts'/item['file'];assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
actual=read('p15-browser-build-hashes.json');assert actual['datasetWasmMatchesRuntimeArtifactReport']
for item in actual['files']:
 if item['file'].endswith('main.dart.js'):assert item['archivedBytes']is False
 else:
  f=root/'runtime-artifacts'/Path(item['file']).name;assert hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
for item in read('source-lock.json')['files']:
 f=root/'source'/item['path'];assert f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256']
 if args.source:
  current=workspace/item['path'];assert current.is_file() and hashlib.sha256(current.read_bytes()).hexdigest()==item['sha256'],item['path']
r=read('result.json');assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and not r['parityCases'] and r['android']=='unrun'
assert r['fullParityGate']=={'status':'rejected-expected','exitCode':1}
print(f'P15: {len(m["files"])} artifacts verified; concurrent rule/undo increment passed; full product NOT COMPLETE')
