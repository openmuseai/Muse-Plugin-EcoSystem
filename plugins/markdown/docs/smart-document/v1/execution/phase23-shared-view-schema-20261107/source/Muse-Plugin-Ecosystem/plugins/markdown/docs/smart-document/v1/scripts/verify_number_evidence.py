#!/usr/bin/env python3
"""Verify immutable P20 exact-number UI, collaboration and cold readback evidence."""
import argparse
import hashlib
import json
import re
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', action='store_true')
p.add_argument('--root', type=Path)
a = p.parse_args()
docs = Path(__file__).resolve().parents[1]
root = a.root or docs / 'execution/phase20-numeric-integrity-20261107'
workspace = docs.parents[5]
def read(name): return json.loads((root / name).read_text())
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

manifest = read('manifest.json')
for item in manifest['files']:
    f = root / item['path']
    assert f.resolve().is_relative_to(root.resolve()) and f.is_file() and not f.is_symlink()
    assert f.stat().st_size == item['bytes'] and sha(f) == item['sha256'], item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()} - {'manifest.json'} == {e['path'] for e in manifest['files']}
for platform in ['macos', 'ios']:
    report, primary, reopen = (read(platform + '/' + n) for n in ['result.json', 'number-e2e.json', 'number-reopen.json'])
    assert report['status'] == 'passed-number-slice'
    assert (report['primaryChecks'], report['freshProcessChecks']) == (8, 3)
    assert primary['status'] == reopen['status'] == 'passed'
    assert primary['run'] == reopen['run'] == report['run']
    for key in ['objectId', 'datasetObjectId']:
        assert primary[key] == reopen[key]
    assert len(primary['checks']) == len(set(primary['checks'])) == 8
    assert len(reopen['checks']) == 3 and primary['input'] == '42.125'
    cell = primary['views'][0]['rows'][0]['cells'][primary['fieldId']]
    assert cell['numberInput'] == cell['raw']['data'] == '42.125'
    for name in ['number_document_test.dart.log', 'number_reopen_test.dart.log']:
        log = (root / platform / name).read_text()
        assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
native, config = read('macos/number-e2e.json'), read('number-web-public.json')
for key, config_key in [('objectId', 'NUMBER_OBJECT'), ('datasetObjectId', 'NUMBER_DATASET'), ('rowId', 'NUMBER_ROW'), ('fieldId', 'NUMBER_FIELD')]:
    assert native[key] == config[config_key]
for name, count in [('number-web-result.json', 9), ('number-web-peer.json', 5), ('number-web-reload.json', 5), ('number-native-web-readback.json', 4)]:
    result = read(name)
    assert result['status'] == 'passed' and len(result['checks']) == len(set(result['checks'])) == count
    for key in ['objectId', 'datasetObjectId', 'rowId', 'fieldId']:
        assert result[key] == native[key], (name, key)
    if name != 'number-native-web-readback.json':
        assert result['value'] == '12345678901234567890.12345678' and result['numberFormat'] == 1
assert 'test result: ok. 56 passed; 0 failed' in (root / 'p20-number-core-third.log').read_text()
for name, count in [('p20-number-widget-focus.log', 3), ('p20-dataset-full-first.log', 54), ('p20-dataset-sdk-tests.log', 3)]:
    assert f'+{count}: All tests passed!' in (root / name).read_text(), name
for name in ['p20-dataset-analysis-final.log', 'p20-example-analysis-final.log', 'p20-web-analysis-second.log']:
    assert 'No issues found!' in (root / name).read_text()
assert 'All tests passed!' in (root / 'p20-native-web-readback.log').read_text()
for name, needles in [
    ('number-web-exact-draft.ax.txt', ['9007199254740993.123456789']),
    ('number-web-invalid.ax.txt', ['123abc', '请输入有效数字']),
    ('number-web-cell-conflict.ax.txt', ['777.123456789', '内容已被修改']),
    ('number-web-field-conflict.ax.txt', ['888.125', '字段设置已被修改']),
    ('number-web-final.ax.txt', ['PASS · 9 项']),
    ('number-web-reload.ax.txt', ['PASS · 5 项', '只读'])]:
    text = (root / name).read_text()
    assert all(needle in text for needle in needles), name
assert 'FAILED' in (root / 'diagnostic/original-input-boundary-failure.log').read_text()
assert 'NUMBER_DRAFT_DIAGNOSTIC=' in (root / 'diagnostic/input-focus-diagnostic.log').read_text()
build = read('p20-browser-build-hashes.json')
assert build['allRuntimeArtifactsMatchReports'] and len(build['files']) == 7
for f in build['files']:
    if f['file'] == 'main.dart.js': assert f['archivedBytes'] is False
    else: assert sha(root / 'runtime-artifacts' / f['domain'] / f['file']) == f['sha256']
lock = read('source-lock.json')
for f in lock['files']:
    assert sha(root / 'source' / f['path']) == f['sha256'], f['path']
    if a.source: assert sha(workspace / f['path']) == f['sha256'], f['path']
assert all(r['exitCode'] == 0 for r in read('p20-frozen-baselines.json'))
assert read('p19-cloud-binary.json')['change'].startswith('original Yrs 0.23.5')
result = read('result.json')
assert result['status'] == 'partial' and result['fullProductAcceptance'] == 'not-complete'
assert result['parityCases'] == [] and result['android'] == 'unrun'
assert 'Full parity gate rejected' in (root / 'full-parity-gate.log').read_text()
print(f'P20 evidence valid: {len(manifest["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
