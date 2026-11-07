#!/usr/bin/env python3
"""Verify P23 original shared schema, concurrent view/field branches and UI receipts."""
import argparse
import hashlib
import json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',action='store_true');p.add_argument('--root',type=Path);a=p.parse_args()
docs=Path(__file__).resolve().parents[1];workspace=docs.parents[5]
root=a.root or docs/'execution/phase23-shared-view-schema-20261107'
def read(name):return json.loads((root/name).read_text())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
manifest=read('manifest.json')
for item in manifest['files']:
    f=root/item['path'];assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
    assert f.stat().st_size==item['bytes'] and sha(f)==item['sha256'],item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()}-{'manifest.json'}=={e['path'] for e in manifest['files']}
for platform in ['macos','ios']:
    report,primary,reopen=(read(platform+'/'+n) for n in ['result.json','schema-view-e2e.json','schema-view-reopen.json'])
    assert report['status']=='passed-schema-view-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(11,3)
    assert primary['status']==reopen['status']=='passed' and primary['run']==reopen['run']==report['run']
    for key in ['objectId','datasetObjectId']:assert primary[key]==reopen[key]
    assert len(primary['checks'])==len(set(primary['checks']))==11 and len(reopen['checks'])==3
    assert 'actual-local-view-switch-clears-obsolete-cell-presence-without-writing-content' in primary['checks']
    assert len(primary['views'])==3
    split=primary['split'];assert (split['aliceViews'],split['bobViews'],split['aliceRows'],split['bobRows'])==(2,1,1,2)
    assert split['heldOriginalFrames']['alice']>0 and split['blockedHttpRequests']>0
    for name in ['schema_view_document_test.dart.log','schema_view_reopen_test.dart.log']:
        log=(root/platform/name).read_text();assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
native,config=read('macos/schema-view-e2e.json'),read('schema-view-web-public.json')
for key,ck in [('objectId','SCHEMA_VIEW_OBJECT'),('datasetObjectId','SCHEMA_VIEW_DATASET'),('firstViewId','SCHEMA_VIEW_FIRST'),('linkedViewId','SCHEMA_VIEW_NATIVE_LINKED'),('temporaryViewId','SCHEMA_VIEW_NATIVE_TEMPORARY'),('rowId','SCHEMA_VIEW_NATIVE_ROW')]:assert native[key]==config[ck]
for name,count in [('schema-view-web-result.json',13),('schema-view-web-peer.json',9),('schema-view-web-reload.json',5),('schema-view-native-web-readback.json',7)]:
    result=read(name)
    assert result['status']=='passed' and len(result['checks'])==len(set(result['checks']))==count
    assert result['objectId']==native['objectId'] and result['datasetObjectId']==native['datasetObjectId']
assert native['fieldId']==config['SCHEMA_VIEW_NATIVE_FIELD']
for platform in ['macos','ios']:
    evidence=read(platform+'/schema-view-e2e.json')
    assert (evidence['split']['aliceFields'],evidence['split']['bobFields'])==(3,4)
    assert all(any(f['id']==evidence['fieldId'] for f in v['columns']) for v in evidence['views'])
    for v in evidence['views']:
        row=next(row for row in v['rows'] if row['id']==evidence['rowId'])
        assert row['cells'][evidence['fieldId']]['value']=='字段并发值'
alice,bob,offline=(read('schema-view-web-'+n+'.json') for n in ['result','peer','reload'])
def views(result):return {v['id']:v for v in result['views']}
assert views(alice)==views(bob)==views(offline)
assert len(alice['views'])==5
assert (alice['branch']['viewCount'],alice['branch']['rowCount'])==(4,2)
assert (bob['branch']['viewCount'],bob['branch']['rowCount'])==(3,3)
assert all(r['branch']['httpHeld']==1 and r['branch']['heldFrames']>0 for r in [alice,bob])
assert 'peer-observes-obsolete-cell-position-cleared-after-actual-view-switch' in bob['checks']
for result in [bob,offline,read('schema-view-native-web-readback.json')]:
    for key in ['webViewId','temporaryViewId','peerRowId','peerFieldId']:assert result[key]==alice[key]
assert (alice['branch']['fieldCount'],bob['branch']['fieldCount'])==(4,5)
expected={'title','done','url',native['fieldId'],alice['peerFieldId']}
assert all(set(v['fieldIds'])==expected for result in [alice,bob,offline] for v in result['views'])
assert 'Web字段值' in (root/'schema-view-web-final.ax.txt').read_text()
assert 'Web共享字段' in (root/'schema-view-web-field-edit.ax.txt').read_text()
by_id=views(alice);base=by_id[native['firstViewId']];web=by_id[alice['webViewId']];temporary=by_id[alice['temporaryViewId']]
assert len(base['rowIds'])==3 and web['rowIds']==[alice['peerRowId']] and web['filterCount']==1 and web['name']=='Web远端视图'
assert set(temporary['rowIds'])==set(base['rowIds']) and temporary['name']=='Web临时视图'
original=next(v for v in native['views'] if v['id']==native['firstViewId'])
assert set(base['rowIds'])=={r['id'] for r in original['rows']}|{alice['peerRowId']}
assert any(e['action']=='undo' and e['applied'] and alice['temporaryViewId'] not in e['viewIds'] for e in alice['history'])
assert any(e['action']=='redo' and e['applied'] and alice['temporaryViewId'] in e['viewIds'] for e in alice['history'])
assert 'test result: ok. 63 passed; 0 failed' in (root/'p23-fields-core-final.log').read_text()
for name,count in [('p23-dataset-full.log',60),('p23-dataset-sdk-tests.log',3)]:assert f'+{count}: All tests passed!' in (root/name).read_text(),name
for name in ['p23-dataset-analysis.log','p23-example-analysis.log','p23-web-analysis-first.log']:assert 'No issues found!' in (root/name).read_text()
assert 'All tests passed!' in (root/'p23-native-web-readback.log').read_text()
assert 'FAILED' in (root/'diagnostic/original-field-order-failure.log').read_text()
assert 'Bad state: No element' in (root/'diagnostic/unbuilt-second-row/schema_view_document_test.dart.log').read_text()
assert 'outside the bounds of the root' in (root/'diagnostic/offscreen-full-list-center/schema_view_document_test.dart.log').read_text()
for name,needles in [
    ('schema-view-web-alice-branch.ax.txt',['阶段 2 · 4 个视图','原主成员 2']),
    ('schema-view-web-bob-branch.ax.txt',['阶段 2 · 3 个视图','原主成员 3']),
    ('schema-view-web-base.ax.txt',['第 3 行，标题 Web新记录']),
    ('schema-view-web-filter.ax.txt',['显示 1 / 3 条记录','Web团队视图']),
    ('schema-view-web-stale.ax.txt',['本地旧视图','视图已变化或名称无效']),
    ('schema-view-web-missing.ax.txt',['指定视图不可用，原引用保留','选择视图']),
    ('schema-view-web-presence-before.ax.txt',['Web团队视图 · 第 1 条 · Web共享字段']),
    ('schema-view-web-presence-cleared.ax.txt',['协作者 在线']),
    ('schema-view-web-final.ax.txt',['PASS · 13 项']),
    ('schema-view-web-peer.ax.txt',['PASS · 9 项']),
    ('schema-view-web-reload.ax.txt',['PASS · 5 项','只读'])]:
    assert all(needle in (root/name).read_text() for needle in needles),name
assert 'Web团队视图 · 第 1 条 · Web共享字段' not in (root/'schema-view-web-presence-cleared.ax.txt').read_text()
build=read('p23-browser-build-hashes.json');assert build['allRuntimeArtifactsMatchReports'] and len(build['files'])==7
for item in build['files']:
    if item['file']=='main.dart.js':assert item['archivedBytes'] is False
    else:assert sha(root/'runtime-artifacts'/item['domain']/item['file'])==item['sha256']
lock=read('source-lock.json')
for item in lock['files']:
    assert sha(root/'source'/item['path'])==item['sha256'],item['path']
    if a.source:assert sha(workspace/item['path'])==item['sha256'],item['path']
assert all(r['exitCode']==0 for r in read('p23-frozen-baselines.json'))
assert 'shared original FieldMap projection verified' in (root/'p23-schema-reference-qualified.log').read_text()
result=read('result.json');assert result['status']=='partial' and result['fullProductAcceptance']=='not-complete'
assert result['parityCases']==[] and result['android']=='unrun' and 'Full parity gate rejected' in (root/'full-parity-gate.log').read_text()
print(f'P23 evidence valid: {len(manifest["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
