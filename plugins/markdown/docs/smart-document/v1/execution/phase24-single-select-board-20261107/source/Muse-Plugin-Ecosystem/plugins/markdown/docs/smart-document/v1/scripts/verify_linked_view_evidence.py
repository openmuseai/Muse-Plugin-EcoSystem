#!/usr/bin/env python3
"""Verify P22 original linked views, independent branches and real UI receipts."""
import argparse
import hashlib
import json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',action='store_true');p.add_argument('--root',type=Path);a=p.parse_args()
docs=Path(__file__).resolve().parents[1];workspace=docs.parents[5]
root=a.root or docs/'execution/phase22-linked-database-views-20261107'
def read(name):return json.loads((root/name).read_text())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
manifest=read('manifest.json')
for item in manifest['files']:
    f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
    assert f.stat().st_size==item['bytes'] and sha(f)==item['sha256'],item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()}-{'manifest.json'}=={e['path'] for e in manifest['files']}
for platform in ['macos','ios']:
    report,primary,reopen=(read(platform+'/'+n) for n in ['result.json','linked-view-e2e.json','linked-view-reopen.json'])
    assert report['status']=='passed-linked-view-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(9,3)
    assert primary['status']==reopen['status']=='passed' and primary['run']==reopen['run']==report['run']
    for key in ['objectId','datasetObjectId']:assert primary[key]==reopen[key]
    assert len(primary['checks'])==len(set(primary['checks']))==9 and len(reopen['checks'])==3
    assert 'actual-local-view-switch-clears-obsolete-cell-presence-without-writing-content' in primary['checks']
    assert len(primary['views'])==3
    split=primary['split'];assert (split['aliceViews'],split['bobViews'],split['aliceRows'],split['bobRows'])==(2,1,1,2)
    assert split['heldOriginalFrames']['alice']>0 and split['blockedHttpRequests']>0
    for name in ['linked_view_document_test.dart.log','linked_view_reopen_test.dart.log']:
        log=(root/platform/name).read_text();assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
native,config=read('macos/linked-view-e2e.json'),read('linked-view-web-public.json')
for key,ck in [('objectId','LINKED_VIEW_OBJECT'),('datasetObjectId','LINKED_VIEW_DATASET'),('firstViewId','LINKED_VIEW_FIRST'),('linkedViewId','LINKED_VIEW_NATIVE_LINKED'),('temporaryViewId','LINKED_VIEW_NATIVE_TEMPORARY'),('rowId','LINKED_VIEW_NATIVE_ROW')]:assert native[key]==config[ck]
for name,count in [('linked-view-web-result.json',10),('linked-view-web-peer.json',8),('linked-view-web-reload.json',5),('linked-view-native-web-readback.json',6)]:
    result=read(name)
    assert result['status']=='passed' and len(result['checks'])==len(set(result['checks']))==count
    assert result['objectId']==native['objectId'] and result['datasetObjectId']==native['datasetObjectId']
alice,bob,offline=(read('linked-view-web-'+n+'.json') for n in ['result','peer','reload'])
def views(result):return {v['id']:v for v in result['views']}
assert views(alice)==views(bob)==views(offline)
assert len(alice['views'])==5
assert (alice['branch']['viewCount'],alice['branch']['rowCount'])==(4,2)
assert (bob['branch']['viewCount'],bob['branch']['rowCount'])==(3,3)
assert all(r['branch']['httpHeld']==1 and r['branch']['heldFrames']>0 for r in [alice,bob])
assert 'peer-observes-obsolete-cell-position-cleared-after-actual-view-switch' in bob['checks']
for result in [bob,offline,read('linked-view-native-web-readback.json')]:
    for key in ['webViewId','temporaryViewId','peerRowId']:assert result[key]==alice[key]
by_id=views(alice);base=by_id[native['firstViewId']];web=by_id[alice['webViewId']];temporary=by_id[alice['temporaryViewId']]
assert len(base['rowIds'])==3 and web['rowIds']==[alice['peerRowId']] and web['filterCount']==1 and web['name']=='Web远端视图'
assert set(temporary['rowIds'])==set(base['rowIds']) and temporary['name']=='Web临时视图'
original=next(v for v in native['views'] if v['id']==native['firstViewId'])
assert set(base['rowIds'])=={r['id'] for r in original['rows']}|{alice['peerRowId']}
assert any(e['action']=='undo' and e['applied'] and alice['temporaryViewId'] not in e['viewIds'] for e in alice['history'])
assert any(e['action']=='redo' and e['applied'] and alice['temporaryViewId'] in e['viewIds'] for e in alice['history'])
assert 'test result: ok. 62 passed; 0 failed' in (root/'p22-core-final.log').read_text()
for name,count in [('p22-linked-view-widget-first.log',3),('p22-selection-widget.log',3),('p22-dataset-flutter-full.log',60),('p22-dataset-sdk-tests.log',3)]:assert f'+{count}: All tests passed!' in (root/name).read_text(),name
for name in ['p22-dataset-analysis-final.log','p22-example-analysis-final.log','p22-web-presence-analysis.log']:assert 'No issues found!' in (root/name).read_text()
assert 'All tests passed!' in (root/'p22-native-web-final-readback.log').read_text()
assert 'FAILED' in (root/'diagnostic/original-view-membership-failure.log').read_text()
for platform in ['macos','ios']:assert read('diagnostic/before-presence/'+platform+'/result.json')['primaryChecks']==8
for name,needles in [
    ('linked-view-web-alice-branch.ax.txt',['阶段 2 · 4 个视图','原主成员 2']),
    ('linked-view-web-bob-branch.ax.txt',['阶段 2 · 3 个视图','原主成员 3']),
    ('linked-view-web-base.ax.txt',['第 3 行，标题 Web新记录']),
    ('linked-view-web-filter.ax.txt',['显示 1 / 3 条记录','Web团队视图']),
    ('linked-view-web-stale.ax.txt',['本地旧视图','视图已变化或名称无效']),
    ('linked-view-web-missing.ax.txt',['指定视图不可用，原引用保留','选择视图']),
    ('linked-view-web-presence-before.ax.txt',['Web团队视图 · 第 1 条 · 标题']),
    ('linked-view-web-presence-cleared.ax.txt',['协作者 在线']),
    ('linked-view-web-final.ax.txt',['PASS · 10 项']),
    ('linked-view-web-peer.ax.txt',['PASS · 8 项']),
    ('linked-view-web-reload.ax.txt',['PASS · 5 项','只读'])]:
    assert all(needle in (root/name).read_text() for needle in needles),name
assert 'Web团队视图 · 第 1 条 · 标题' not in (root/'linked-view-web-presence-cleared.ax.txt').read_text()
build=read('p22-browser-build-hashes.json');assert build['allRuntimeArtifactsMatchReports'] and len(build['files'])==7
for item in build['files']:
    if item['file']=='main.dart.js':assert item['archivedBytes'] is False
    else:assert sha(root/'runtime-artifacts'/item['domain']/item['file'])==item['sha256']
lock=read('source-lock.json')
for item in lock['files']:
    assert sha(root/'source'/item['path'])==item['sha256'],item['path']
    if a.source:assert sha(workspace/item['path'])==item['sha256'],item['path']
assert all(r['exitCode']==0 for r in read('p22-frozen-baselines.json'))
assert 'original linked-view/inline membership reuse verified' in (root/'p22-view-reference.log').read_text()
result=read('result.json');assert result['status']=='partial' and result['fullProductAcceptance']=='not-complete'
assert result['parityCases']==[] and result['android']=='unrun' and 'Full parity gate rejected' in (root/'full-parity-gate.log').read_text()
print(f'P22 evidence valid: {len(manifest["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
