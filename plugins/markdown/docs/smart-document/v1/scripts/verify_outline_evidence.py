#!/usr/bin/env python3
"""Verify immutable P19 outline/UI and original GC deletion-tail repair evidence."""
import argparse,hashlib,json,re
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');p.add_argument('--root',type=Path);a=p.parse_args()
docs=Path(__file__).resolve().parents[1];root=a.root or docs/'execution/phase19-document-outline-20261107';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
m=read('manifest.json')
for item in m['files']:
 f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
 assert f.stat().st_size==item['bytes'] and sha(f)==item['sha256'],item['path']
assert {str(f.relative_to(root))for f in root.rglob('*')if f.is_file()}-{'manifest.json'}=={e['path']for e in m['files']}
for platform in ['macos','ios']:
 r=read(platform+'/result.json');v=read(platform+'/outline-e2e.json');o=read(platform+'/outline-reopen.json')
 assert r['status']=='passed-outline-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(8,3)
 assert v['status']==o['status']=='passed' and v['run']==o['run']==r['run'] and v['objectId']==o['objectId']
 assert len(v['checks'])==len(set(v['checks']))==8 and len(o['checks'])==3
 assert v['outline']['ready'] is True and [e['level']for e in v['outline']['entries']]==[1,3,2]
 assert v['outline']['entries'][1]['blockId']==v['headingId']
 assert 'gc-prefix-restored-heading-delete-persists-through-original-cloud-and-fresh-kernel-readback'in v['checks']
 for name in ['outline_document_test.dart.log','outline_reopen_test.dart.log']:
  log=(root/platform/name).read_text();assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log
native=read('macos/outline-e2e.json');config=read('outline-web-public.json')
assert config['OUTLINE_OBJECT']==native['objectId'] and config['OUTLINE_HEADING']==native['headingId']
for name,count in [('outline-web-result.json',8),('outline-web-peer.json',5),('outline-web-reload.json',4),('outline-native-web-readback.json',4)]:
 r=read(name);assert r['status']=='passed' and r['objectId']==native['objectId']
 assert len(r['checks'])==len(set(r['checks']))==count,name
assert read('outline-web-result.json')['outline']==read('outline-web-peer.json')['outline']==read('outline-web-reload.json')['outline']
assert read('outline-web-result.json')['outline']['entries'][1]['text']=='Web 重连 远端 协作章节😀'
for name,count in [('p19-document-selected-fixed.log',46),('p19-document-cloud-isolated.log',1),('p19-dataset-full-fixed.log',51),('p19-dataset-sdk-tests.log',3)]:assert f'+{count}: All tests passed!'in(root/name).read_text(),name
for name,count in [('p19-core-tests-qualified.log',27),('p19-dataset-core-tests.log',50)]:assert f'test result: ok. {count} passed; 0 failed'in(root/name).read_text(),name
assert 'test result: ok. 305 passed; 0 failed; 1 ignored'in(root/'p19-yrs-complete-suite.log').read_text()
for name in ['p19-document-analysis-final.log','p19-example-analysis-final.log','p19-dataset-analysis-final.log','p19-web-analysis-fixed.log']:assert 'No issues found!'in(root/name).read_text(),name
assert 'All tests passed!'in(root/'p19-native-web-readback.log').read_text()
assert 'FAILED'in(root/'diagnostic/p19-captured-delete-first.log').read_text()
assert 'test result: ok. 1 passed; 0 failed'in(root/'diagnostic/p19-captured-delete-fixed.log').read_text()
assert '298 passed; 7 failed; 1 ignored'in(root/'diagnostic/p19-yrs-all-tests.log').read_text()
assert 'No such file or directory'in(root/'diagnostic/p19-yrs-all-tests.log').read_text()
for name,needle in [('outline-web-collapsed.ax.txt','展开子目录'),('outline-web-navigation.ax.txt','Web 重连 远端 协作章节'),('outline-web-final.ax.txt','PASS · 8 项'),('outline-web-reload.ax.txt','PASS · 4 项')]:assert needle in(root/name).read_text(),name
assert not re.search(r'button[^\n]*协作章节',(root/'outline-web-collapsed.ax.txt').read_text())
assert not re.search(r'button[^\n]*协作章节',(root/'outline-web-deletion.ax.txt').read_text())
build=read('p19-browser-build-hashes.json');assert build['allRuntimeArtifactsMatchReports'] is True and len(build['files'])==7
for f in build['files']:
 if f['file'].endswith('main.dart.js'):assert f['archivedBytes'] is False
 else:assert sha(root/'runtime-artifacts'/f['domain']/Path(f['file']).name)==f['sha256']
lock=read('source-lock.json')
for f in lock['files']:
 assert sha(root/'source'/f['path'])==f['sha256'],f['path']
 if a.source:assert sha(workspace/f['path'])==f['sha256'],f['path']
base='Muse-Plugin-Ecosystem/plugins/markdown/smart_document'
fixtures=read('p19-yrs-fixtures.json');assert fixtures['revision']=='3996e91df00acdb67334695944bc43f60627103f' and len(fixtures['files'])==9
for f in fixtures['files']:
 b=(root/'source'/base/'.build/yrs-test-workspace'/f['path']).read_bytes()
 assert len(b)==f['bytes'] and hashlib.sha256(b).hexdigest()==f['sha256']
 assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==f['gitBlob']
client=root/'source'/base/'vendor/yrs';server=root/'source/Muse-Server/AppFlowy-Cloud/vendor/yrs'
assert sha(client/'src/transaction.rs')==sha(server/'src/transaction.rs')
assert len(json.loads((client/'openmuse-upstream.json').read_text())['patches'])==2
assert len(json.loads((server/'openmuse-upstream.json').read_text())['patches'])==1
assert read('p19-cloud-binary.json')['change'].startswith('original Yrs 0.23.5')
assert all(r['exitCode']==0 for r in read('p19-frozen-baselines.json'))
r=read('result.json');assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and r['parityCases']==[] and r['android']=='unrun'
assert 'Full parity gate rejected'in(root/'full-parity-gate.log').read_text()
print(f'P19 evidence valid: {len(m["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
