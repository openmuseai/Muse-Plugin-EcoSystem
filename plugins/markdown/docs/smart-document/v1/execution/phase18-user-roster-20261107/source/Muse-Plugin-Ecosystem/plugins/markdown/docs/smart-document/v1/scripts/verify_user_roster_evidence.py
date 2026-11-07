#!/usr/bin/env python3
"""Verify immutable P18 authenticated user / position roster qualification."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');args=p.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase18-user-roster-20261107';workspace=docs.parents[5]
def read(name):return json.loads((root/name).read_text())
m=read('manifest.json')
for item in m['files']:
 f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
 assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()}-{'manifest.json'}=={i['path'] for i in m['files']}
for platform in ['macos','ios']:
 a=read(platform+'/users-e2e.json');b=read(platform+'/users-reopen.json');r=read(platform+'/result.json')
 assert r['status']=='passed-users-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(8,3)
 assert a['status']==b['status']=='passed' and a['run']==b['run']==r['run']
 assert a['objectId']==b['objectId'] and a['datasetObjectId']==b['datasetObjectId'] and a['objectId']!=a['datasetObjectId']
 assert a['target']['selector']['objectId']==a['datasetObjectId']
 assert len(a['views'][0]['rows'])==1
 assert len(set(a['uids'].values()))==2 and all(isinstance(v,str) and str(int(v))==v and 0<int(v)<=9223372036854775807 for v in a['uids'].values())
 for name in ['user_presence_document_test.dart.log','user_presence_reopen_test.dart.log']:
  log=(root/platform/name).read_text();assert 'All tests passed!'in log and 'Warning: A call to tap()'not in log
native=read('macos/users-e2e.json');config=read('users-web-public.json')
for name,count in [('users-web-result.json',20),('users-web-peer-primary.json',5),('users-web-peer-two.json',5),('users-web-self-other.json',5),('users-web-reload.json',4),('users-native-web-readback.json',4)]:
 r=read(name);assert r['status']=='passed' and len(r['checks'])==len(set(r['checks']))==count
 for key in ['objectId','datasetObjectId']:assert r[key]==native[key],(name,key)
 if 'uid'in r and r['platform']!='web-reload':assert r['uid']==native['uids'][r['actor']]
r=read('users-web-result.json')
assert r['metrics']==[{'stage':i,'remotePositions':positions,'users':users,'bobPositions':bob} for i,(positions,users,bob) in enumerate([(3,2,2),(2,2,1),(1,1,0),(0,1,0),(1,2,1)])]
assert config['USERS_ALICE_UID']==native['uids']['alice'] and config['USERS_BOB_UID']==native['uids']['bob']
assert read('users-native-web-readback.json')['rowId']==native['views'][0]['rows'][0]['id']
for name,count in [('p18-contract-tests.log',5),('p18-realtime-tests-fourth.log',4),('p18-widgets-tests-qualified.log',5),('p18-dataset-full-qualified.log',51),('p18-document-selected-qualified.log',43),('p18-document-cloud-isolated.log',1)]:assert f'+{count}: All tests passed!'in(root/name).read_text(),name
assert 'test result: ok. 6 passed; 0 failed'in(root/'p18-profile-core-tests.log').read_text()
for name in ['p18-contract-analysis.log','p18-realtime-analysis-qualified.log','p18-widgets-analysis-qualified.log','p18-dataset-analysis-qualified.log','p18-document-analysis-qualified.log','p18-example-analysis-qualified.log','p18-web-analysis-second.log']:assert 'No issues found!'in(root/name).read_text(),name
assert 'All tests passed!'in(root/'p18-native-web-readback.log').read_text()
assert 'Connection refused'in(root/'diagnostic/p18-dataset-full-first.log').read_text()
assert 'SOURCE_UNAVAILABLE'in(root/'diagnostic/p18-document-full-first.log').read_text()
for name,needle in [('users-web-four-positions.ax.txt','原连接 3/3'),('users-web-dataset-roster.ax.txt','在线位置 2'),('users-web-one-peer-left.ax.txt','完成 · 正在编辑'),('users-web-own-other-only.ax.txt','button 1 人'),('users-web-local-only.ax.txt','原连接 0/0'),('users-web-final.ax.txt','PASS · 20 checks'),('users-web-reload.ax.txt','PASS · 4 checks')]:assert needle in(root/name).read_text(),name
build=read('p18-browser-build-hashes.json');assert build['allRuntimeArtifactsMatchReports'] is True
for f in build['files']:
 if f['file'].endswith('main.dart.js'):assert f['archivedBytes'] is False
 else:assert hashlib.sha256((root/'runtime-artifacts'/f['domain']/Path(f['file']).name).read_bytes()).hexdigest()==f['sha256']
assert read('p18-profile-cors.json')=={'status':200,'allowedOrigin':'http://127.0.0.1:50946','uidMatchesNative':True}
r=read('result.json');assert r['status']=='partial' and r['fullProductAcceptance']=='not-complete' and r['parityCases']==[] and r['android']=='unrun'
assert 'Full parity gate rejected'in(root/'full-parity-gate.log').read_text()
lock=read('source-lock.json')
for f in lock['files']:
 assert hashlib.sha256((root/'source'/f['path']).read_bytes()).hexdigest()==f['sha256']
 if args.source:assert hashlib.sha256((workspace/f['path']).read_bytes()).hexdigest()==f['sha256'],f['path']
print(f'P18 evidence valid: {len(m["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
