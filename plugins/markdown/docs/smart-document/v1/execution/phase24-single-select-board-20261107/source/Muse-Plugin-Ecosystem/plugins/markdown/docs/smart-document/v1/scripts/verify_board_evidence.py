#!/usr/bin/env python3
"""Verify P24 original board identities, true independent branches and actual UI receipts."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');p.add_argument('--root',type=Path);a=p.parse_args()
docs=Path(__file__).resolve().parents[1];workspace=docs.parents[5];root=a.root or docs/'execution/phase24-single-select-board-20261107'
def read(name):return json.loads((root/name).read_text())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
manifest=read('manifest.json')
for item in manifest['files']:
 f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink();assert f.stat().st_size==item['bytes'] and sha(f)==item['sha256'],item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()}-{'manifest.json'}=={e['path'] for e in manifest['files']}
for platform in ['macos','ios']:
 report,primary,reopen=(read(platform+'/'+n) for n in ['result.json','board-e2e.json','board-reopen.json'])
 assert report['status']=='passed-board-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(9,3)
 assert primary['status']==reopen['status']=='passed' and primary['run']==reopen['run']==report['run']
 for key in ['objectId','datasetObjectId']:assert primary[key]==reopen[key]
 assert len(primary['checks'])==len(set(primary['checks']))==9 and len(reopen['checks'])==3
 assert len(primary['views'])==2
 split=primary['split'];assert (split['aliceViews'],split['bobViews'],split['aliceRows'],split['bobRows'])==(2,1,1,2)
 board=next(v for v in primary['views'] if v['id']==primary['boardViewId'])
 assert board['layout']==1 and board['board']['ready'] and board['board']['fieldId']==primary['fieldId']
 assert next(g for g in board['board']['groups'] if g['id']==primary['doneId'])['rowIds']==[r['id'] for r in board['rows']]
 for name in ['board_document_test.dart.log','board_reopen_test.dart.log']:
  log=(root/platform/name).read_text();assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
native,config=read('macos/board-e2e.json'),read('board-web-public.json')
for key,ck in [('objectId','BOARD_OBJECT'),('datasetObjectId','BOARD_DATASET'),('firstViewId','BOARD_FIRST'),('boardViewId','BOARD_NATIVE'),('rowId','BOARD_ROW'),('fieldId','BOARD_FIELD')]:assert native[key]==config[ck]
for name,count in [('board-web-result.json',11),('board-web-peer.json',10),('board-web-reload.json',6),('p24-native-web-readback.json',7)]:
 result=read(name);assert result['status']=='passed' and len(result['checks'])==len(set(result['checks']))==count
 assert result['objectId']==native['objectId'] and result['datasetObjectId']==native['datasetObjectId']
alice,bob,offline=(read('board-web-'+n+'.json') for n in ['result','peer','reload'])
def views(result):return {v['id']:v for v in result['views']}
assert views(alice)==views(bob)==views(offline)
assert (alice['branch']['viewCount'],alice['branch']['rowCount'])==(3,2)
assert (bob['branch']['viewCount'],bob['branch']['rowCount'])==(2,3)
assert all(r['branch']['httpHeld']>0 and r['branch']['heldFrames']>0 for r in [alice,bob])
for result in [bob,offline]:
 for key in ['webViewId','webRowId','fieldId','numberFieldId']:assert result[key]==alice[key]
expected={r['id'] for r in native['views'][0]['rows']}|{alice['webRowId']}
assert len(expected)==3
for v in alice['views']:
 assert set(v['rowIds'])==expected
 if v['layout']==1:assert set(next(g for g in v['groups'] if g['id']==config['BOARD_DONE'])['rowIds'])==expected
assert any(e['action']=='undo' and e['applied'] for e in alice['history']) and any(e['action']=='redo' and e['applied'] for e in alice['history'])
assert 'test result: ok. 66 passed; 0 failed' in (root/'p24-dataset-core.log').read_text()
for name,count in [('p24-dataset-flutter.log',64),('p24-dataset-sdk-tests.log',3)]:assert f'+{count}: All tests passed!' in (root/name).read_text(),name
for name in ['p24-dataset-analysis.log','p24-example-analysis.log','p24-web-analysis.log']:assert 'No issues found!' in (root/name).read_text()
assert 'All tests passed!' in (root/'p24-native-web-readback.log').read_text()
assert read('diagnostic/inter-build-projection-change/result.json')['status']=='failed'
assert 'Expected:' in (root/'diagnostic/inter-build-projection-change/board_reopen_test.dart.log').read_text()
for name,needles in [('alice-branch',['阶段 2 · 3 个视图 · 2 条记录']),('bob-branch',['阶段 2 · 2 个视图 · 3 条记录']),('base',['待处理 · 1','Web任务']),('record',['标题 Web卡片详情','状态 进行中']),('moved',['进行中 · 1','Web卡片详情']),('stale',['操作未完成，请检查内容或保存状态','Web工时：12.5']),('undo',['Web任务','Web工时：12.5']),('final',['Web卡片详情','Web工时：12.5','PASS · 11 项']),('peer',['PASS · 10 项']),('reload',['PASS · 6 项','只读'])]:
 assert all(needle in (root/('board-web-'+name+'.ax.txt')).read_text() for needle in needles),name
build=read('p24-browser-build-hashes.json');assert build['allRuntimeArtifactsMatchReports'] and len(build['files'])==7
for item in build['files']:
 if item['file']=='main.dart.js':assert item['archivedBytes'] is False
 else:assert sha(root/'runtime-artifacts'/item['domain']/item['file'])==item['sha256']
lock=read('source-lock.json')
for item in lock['files']:
 assert sha(root/'source'/item['path'])==item['sha256'],item['path']
 if a.source:assert sha(workspace/item['path'])==item['sha256'],item['path']
assert len(read('p24-frozen-baselines.json'))==21 and all(r['exitCode']==0 for r in read('p24-frozen-baselines.json'))
assert 'eight original board/group references' in (root/'p24-board-reference.log').read_text()
result=read('result.json');assert result['status']=='partial' and result['fullProductAcceptance']=='not-complete' and result['parityCases']==[] and result['android']=='unrun'
assert 'Full parity gate rejected' in (root/'full-parity-gate.log').read_text()
print(f'P24 evidence valid: {len(manifest["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
