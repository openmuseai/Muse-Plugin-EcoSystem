#!/usr/bin/env python3
"""Validate immutable P17 nested original Array/Map rule evidence."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');args=p.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase17-nested-rules-20261107';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
m=read('manifest.json')
for item in m['files']:
 f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
 assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()}-{'manifest.json'}=={i['path'] for i in m['files']}
for platform in ['macos','ios']:
 a=read(platform+'/nested-e2e.json');b=read(platform+'/nested-reopen.json');r=read(platform+'/result.json')
 assert r['status']=='passed-nested-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(7,3)
 assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run']
 assert a['objectId']==b['objectId'] and a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
 assert a['target']['selector']['objectId']==a['datasetObjectId']
 v=a['views'][0];assert v['rulesReady'] and len(v['rows'])==len(v['rowObjects'])==2 and v['filters'][0]['filter_type']==1
 assert [c['content'] for c in v['filters'][0]['children']]==['Muse','B']
 split=a['splitBeforePublish'];assert split['alice']==['Muse A',''] and split['bob']==['Muse','A']
 assert all(split['heldOriginalFrames'][who]>0 for who in ['alice','bob'])
 for name in ['nested_view_document_test.dart.log','nested_view_reopen_test.dart.log']:
  log=(root/platform/name).read_text();assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log
native=read('macos/nested-e2e.json')
for name,count in [('nested-web-result.json',8),('nested-web-peer.json',7),('nested-web-reload.json',5),('nested-native-web-readback.json',4)]:
 r=read(name);assert r['status']=='passed' and len(r['checks'])==len(set(r['checks']))==count
 for key in ['objectId','datasetObjectId','rowA','rowB']:assert r[key]==native[key],(name,key)
a=read('nested-web-result.json');b=read('nested-web-peer.json')
assert a['branch0']=='Muse A/' and b['branch0']=='Muse/B' and a['merge0']==b['merge0']=='Muse A/B'
assert 'test result: ok. 50 passed; 0 failed'in(root/'p17-core-final.log').read_text()
assert '+51: All tests passed!'in(root/'p17-dataset-full.log').read_text()
for name in ['p17-dataset-analysis.log','p17-example-analysis.log','p17-web-analysis.log']:assert 'No issues found!'in(root/name).read_text()
assert 'All tests passed!'in(root/'p17-native-web-readback.log').read_text()
assert '1 failed'in(root/'diagnostic/original-atomic-children-lost-independent-intent.log').read_text()
for name,needle in [('nested-web-alice-split.ax.txt','Children: Muse A/; mode: 0'),('nested-web-bob-split.ax.txt','Children: Muse/B; mode: 0'),('nested-web-merged.ax.txt','Children: Muse A/B; mode: 0'),('nested-web-undo.ax.txt','Children: Muse/B; mode: 0'),('nested-web-redo.ax.txt','Children: Muse A/B; mode: 0'),('nested-web-final.ax.txt','PASS: 8 checks'),('nested-web-peer.ax.txt','PASS: 7 checks'),('nested-web-reload.ax.txt','PASS: 5 checks')]:assert needle in(root/name).read_text(),name
build=read('p17-browser-build-hashes.json');assert build['datasetWasmMatchesRuntimeArtifactReport'] is True
for f in build['files']:
 if f['file'].endswith('main.dart.js'):assert f['archivedBytes'] is False
 else:assert hashlib.sha256((root/'runtime-artifacts'/Path(f['file']).name).read_bytes()).hexdigest()==f['sha256']
r=read('result.json');assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and r['parityCases']==[] and r['android']=='unrun'
assert 'Full parity gate rejected'in(root/'full-parity-gate.log').read_text()
lock=read('source-lock.json')
for f in lock['files']:
 assert hashlib.sha256((root/'source'/f['path']).read_bytes()).hexdigest()==f['sha256']
 if args.source:assert hashlib.sha256((workspace/f['path']).read_bytes()).hexdigest()==f['sha256'],f['path']
print(f'P17 evidence valid: {len(m["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
