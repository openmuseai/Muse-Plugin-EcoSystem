#!/usr/bin/env python3
"""Verify immutable P21 original numeric field settings, full grouping and collaboration evidence."""
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
root = a.root or docs / 'execution/phase21-number-format-settings-20261107'
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
    report, primary, reopen = (read(platform + '/' + n) for n in ['result.json', 'number-format-e2e.json', 'number-format-reopen.json'])
    assert report['status'] == 'passed-number-format-slice'
    assert (report['primaryChecks'], report['freshProcessChecks']) == (11, 3)
    assert primary['status'] == reopen['status'] == 'passed'
    assert primary['run'] == reopen['run'] == report['run']
    for key in ['objectId', 'datasetObjectId']:
        assert primary[key] == reopen[key]
    assert len(primary['checks']) == len(set(primary['checks'])) == 11
    assert len(reopen['checks']) == 3 and primary['input'] == '42.125'
    cell = primary['views'][0]['rows'][0]['cells'][primary['fieldId']]
    assert cell['numberInput'] == cell['raw']['data'] == '42.125'
    for name in ['number_format_document_test.dart.log', 'number_format_reopen_test.dart.log']:
        log = (root / platform / name).read_text()
        assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
native, config = read('macos/number-format-e2e.json'), read('number-format-web-public.json')
for key, config_key in [('objectId', 'NUMBER_FORMAT_OBJECT'), ('datasetObjectId', 'NUMBER_FORMAT_DATASET'), ('rowId', 'NUMBER_FORMAT_ROW'), ('fieldId', 'NUMBER_FORMAT_FIELD')]:
    assert native[key] == config[config_key]
for name, count in [('number-format-web-result.json', 12), ('number-format-web-peer.json', 6), ('number-format-web-reload.json', 5), ('number-format-native-web-readback.json', 4)]:
    result = read(name)
    assert result['status'] == 'passed' and len(result['checks']) == len(set(result['checks'])) == count
    for key in ['objectId', 'datasetObjectId', 'rowId', 'fieldId']:
        assert result[key] == native[key], (name, key)
    if name != 'number-format-native-web-readback.json':
        assert result['value'] == '12345678901234567890.12345678' and result['numberFormat'] == 1
assert 'test result: ok. 58 passed; 0 failed' in (root / 'p21-dataset-rust-final.log').read_text()
for name, count in [('p21-number-format-widget-first.log', 3), ('p21-dataset-flutter-full.log', 57), ('p21-dataset-sdk-tests.log', 3)]:
    assert f'+{count}: All tests passed!' in (root / name).read_text(), name
for name in ['p21-dataset-analysis.log', 'p21-example-analysis.log', 'p21-web-analysis.log']:
    assert 'No issues found!' in (root / name).read_text()
assert 'All tests passed!' in (root / 'p21-native-web-readback.log').read_text()
for name, needles in [
    ('number-format-web-settings.ax.txt', ['数字字段设置', 'Web预算', '欧元']),
    ('number-format-web-cell-conflict.ax.txt', ['777.123456789', '内容已被修改']),
    ('number-format-web-field-conflict.ax.txt', ['888.125', '字段设置已被修改']),
    ('number-format-web-stale.ax.txt', ['旧预算', '字段已变化或名称无效']),
    ('number-format-web-final.ax.txt', ['PASS · 12 项', '$12,345,678,901,234,567,890.12']),
    ('number-format-web-reload.ax.txt', ['PASS · 5 项', '只读'])]:
    text = (root / name).read_text()
    assert all(needle in text for needle in needles), name
assert 'FAILED' in (root / 'diagnostic/original-grouping-failure.log').read_text()
build = read('p21-browser-build-hashes.json')
assert build['allRuntimeArtifactsMatchReports'] and len(build['files']) == 7
for f in build['files']:
    if f['file'] == 'main.dart.js': assert f['archivedBytes'] is False
    else: assert sha(root / 'runtime-artifacts' / f['domain'] / f['file']) == f['sha256']
lock = read('source-lock.json')
for f in lock['files']:
    assert sha(root / 'source' / f['path']) == f['sha256'], f['path']
    if a.source: assert sha(workspace / f['path']) == f['sha256'], f['path']
base = root / 'source/Muse-Plugin-Ecosystem/plugins/markdown/smart_document/vendor/appflowy_database'
pin = json.loads((base / 'openmuse-upstream.json').read_text())
assert len(pin['patches']) == 7
assert sha(base / 'openmuse.patch') == pin['patchSha256']
for item in pin['patches']: assert sha(base / item['file']) == item['sha256']
ref = root / 'source/Muse-Plugin-Ecosystem/plugins/markdown/smart_document/vendor/number_format_reference'
assert sha(ref / 'rusty-money-0.4.1.crate') == '5b28f881005eac7ad8d46b6f075da5f322bd7f4f83a38720fc069694ddadd683'
assert 'bounded pattern reuse verified' in (root / 'p21-format-reference.log').read_text()
assert all(r['exitCode'] == 0 for r in read('p21-frozen-baselines.json'))
assert read('p19-cloud-binary.json')['change'].startswith('original Yrs 0.23.5')
result = read('result.json')
assert result['status'] == 'partial' and result['fullProductAcceptance'] == 'not-complete'
assert result['parityCases'] == [] and result['android'] == 'unrun'
assert 'Full parity gate rejected' in (root / 'full-parity-gate.log').read_text()
print(f'P21 evidence valid: {len(manifest["files"])} artifacts / {len(lock["files"])} source-input snapshots; full product NOT COMPLETE')
