#!/usr/bin/env python3
"""Validate immutable P16 date filter / prefill / hidden record evidence."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');args=p.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase16-date-filters-20261107';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
m=read('manifest.json')
for item in m['files']:
 f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
 assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()}-{'manifest.json'}=={i['path'] for i in m['files']}
for platform in ['macos','ios']:
 a=read(platform+'/date_filter-e2e.json');b=read(platform+'/date_filter-reopen.json');r=read(platform+'/result.json')
 assert r['status']=='passed-date_filter-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(8,3)
 assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run']
 assert a['objectId']==b['objectId'] and a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
 assert a['target']['selector']['objectId']==a['datasetObjectId']
 v=a['views'][0];assert v['rulesReady'] and len(v['rows'])==2 and len(v['rowObjects'])==3 and v['filters'][0]['condition']==0
 assert all(row['cells'][a['fieldId']]['value']['start']=='2026-11-08' for row in v['rows'])
 for name in ['date_filter_document_test.dart.log','date_filter_reopen_test.dart.log']:
  log=(root/platform/name).read_text();assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log
native=read('macos/date_filter-e2e.json')
for name,count in [('date_filter-web-result.json',8),('date_filter-web-peer.json',7),('date_filter-web-reload.json',7),('date_filter-native-web-readback.json',4)]:
 r=read(name);assert r['status']=='passed' and len(r['checks'])==len(set(r['checks']))==count
 for key in ['objectId','datasetObjectId','rowId','fieldId']:assert r[key]==native[key],(name,key)
for name,count in [('p16-core-final.log',44),('p16-original-filters-final.log',21)]:assert f'test result: ok. {count} passed; 0 failed'in(root/name).read_text()
assert '+51: All tests passed!'in(root/'p16-dataset-full-final.log').read_text()
for name in ['p16-dataset-analysis-qualified.log','p16-example-analysis.log','p16-web-analysis-2.log']:assert 'No issues found!'in(root/name).read_text()
assert 'All tests passed!'in(root/'p16-native-web-readback-qualified.log').read_text()
assert 'Test timed out after 30 seconds'in(root/'diagnostic/native-readback-default-timeout.log').read_text()
assert 'HTTP 15'in(root/'date_filter-web-live.ax.txt').read_text() and 'WS更新 1'in(root/'date_filter-web-live.ax.txt').read_text()
assert 'undo,redo'in(root/'date_filter-web-history.ax.txt').read_text()
assert 'PASS · 8 checks'in(root/'date_filter-web-final.ax.txt').read_text()
assert 'PASS · 7 checks'in(root/'date_filter-web-peer.ax.txt').read_text()
assert 'PASS · 7 checks'in(root/'date_filter-web-reload.ax.txt').read_text()
build=read('p16-browser-build-hashes.json');assert build['datasetWasmMatchesRuntimeArtifactReport'] is True
for f in build['files']:
 if f['file'].endswith('main.dart.js'):assert f['archivedBytes'] is False
 else:assert hashlib.sha256((root/'runtime-artifacts'/Path(f['file']).name).read_bytes()).hexdigest()==f['sha256']
r=read('result.json');assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and r['parityCases']==[] and r['android']=='unrun'
assert 'Full parity gate rejected'in(root/'full-parity-gate.log').read_text()
lock=read('source-lock.json')
for f in lock['files']:
 snapshot=root/'source'/f['path'];assert hashlib.sha256(snapshot.read_bytes()).hexdigest()==f['sha256']
 if args.source:assert hashlib.sha256((workspace/f['path']).read_bytes()).hexdigest()==f['sha256'],f['path']
print(f'P16 evidence valid: {len(m["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
