#!/usr/bin/env python3
"""Validate P6 artifacts; an increment must never certify full product parity."""
import argparse,hashlib,json
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',action='store_true');args=parser.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase6-media-20261106';workspace=docs.parents[5]
manifest=json.loads((root/'manifest.json').read_text())
for item in manifest['files']:
    path=root/item['path'];assert path.resolve().is_relative_to(root.resolve()) and path.is_file() and not path.is_symlink()
    assert path.stat().st_size==item['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}-{'manifest.json'}=={p['path'] for p in manifest['files']}
for platform in ['macos','ios']:
    receipt=json.loads((root/platform/'result.json').read_text());a=json.loads((root/platform/'media-e2e.json').read_text());b=json.loads((root/platform/'media-reopen.json').read_text())
    assert receipt['status']=='passed-media-slice' and receipt['primaryChecks']==7 and receipt['freshProcessChecks']==4
    assert a['status']==b['status']=='passed' and a['objectId']==b['objectId'] and a['run']==b['run']==receipt['run']
    assert 'decoded-original-image-frame-visible-after-delete-undo' in a['checks']
    assert 'image-metadata-and-peer-resize-change-actual-rendered-dimensions' in a['checks']
    log=(root/platform/'media_document_test.dart.log').read_text();assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
web=json.loads((root/'web-regression/summary.json').read_text());assert web['status']=='passed' and (web['browserChecks'],web['reloadChecks'],web['nativeReadbackChecks'])==(10,3,6)
assert json.loads((root/'phase6-web-filepicker-readback.json').read_text())['status']=='passed-filepicker-slice'
assert json.loads((root/'database-browser-result.json').read_text())['status']=='passed-runtime-qualification'
result=json.loads((root/'result.json').read_text());assert result['status']=='partial' and result['fullProductAcceptance']=='not-complete' and result['android']=='unrun' and not result['parityCases']
assert result['fullParityGate']=={'status':'rejected-expected','exitCode':1}
if args.source:
    for item in json.loads((root/'source-lock.json').read_text())['files']:
        path=workspace/item['path'];assert path.resolve().is_relative_to(workspace) and path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],item['path']
print(f'P6: {len(manifest["files"])} artifacts verified; link/image increments and database runtime qualification passed; full product NOT COMPLETE')
