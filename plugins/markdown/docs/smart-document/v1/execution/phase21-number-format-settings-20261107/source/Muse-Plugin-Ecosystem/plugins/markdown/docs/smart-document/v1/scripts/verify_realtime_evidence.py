#!/usr/bin/env python3
"""Check immutable P8 evidence, retaining all incomplete full-product gates."""
import argparse
import hashlib
import json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',action='store_true');args=p.parse_args()
docs=Path(__file__).resolve().parents[1];root=docs/'execution/phase8-realtime-20261106';workspace=docs.parents[5]
manifest=json.loads((root/'manifest.json').read_text())
for item in manifest['files']:
    file=root/item['path']
    assert file.resolve().is_relative_to(root.resolve()) and file.is_file() and not file.is_symlink()
    assert file.stat().st_size==item['bytes'] and hashlib.sha256(file.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(root)) for f in root.rglob('*') if f.is_file()}-{'manifest.json'}=={i['path'] for i in manifest['files']}
for platform in ['macos','ios']:
    report=json.loads((root/platform/'result.json').read_text());a=json.loads((root/platform/'realtime-e2e.json').read_text());b=json.loads((root/platform/'realtime-reopen.json').read_text())
    assert report['status']=='passed-realtime-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(8,3)
    assert a['status']==b['status']=='passed' and a['objectId']==b['objectId'] and a['run']==b['run']==report['run']
    for name in ['realtime_document_test.dart.log','realtime_reopen_test.dart.log']:
        log=(root/platform/name).read_text();assert 'All tests passed!' in log and 'Warning: A call to tap()' not in log
for name,count in [('realtime-web-result.json',8),('realtime-web-reload.json',3),('ws2-cloud-qualification.json',7),('realtime-document-adapter-result.json',6),('realtime-permissions-result.json',8)]:
    report=json.loads((root/name).read_text());assert report['status'].startswith('passed') and len(report['checks'])==count
assert json.loads((root/'realtime-web-result.json').read_text())['objectId']==json.loads((root/'realtime-web-reload.json').read_text())['objectId']
boundary=json.loads((root/'ws2-cloud-qualification.json').read_text());assert not boundary['unexpectedNonmemberRead'] and not boundary['unexpectedNonmemberWrite'] and boundary['nonmemberDeniedAtHandshake']
reg=json.loads((root/'regression/summary.json').read_text());assert reg['status']=='passed' and all(x['exitCode']==0 for x in reg['steps'])
result=json.loads((root/'result.json').read_text());assert result['status']=='partial' and result['fullProductAcceptance']=='not-complete' and result['android']=='unrun' and not result['parityCases']
assert result['fullParityGate']=={'status':'rejected-expected','exitCode':1}
assert 'All tests passed!' in (root/'realtime-cross-block-selection.log').read_text()
if args.source:
    for item in json.loads((root/'source-lock.json').read_text())['files']:
        file=workspace/item['path'];assert file.resolve().is_relative_to(workspace) and file.is_file() and hashlib.sha256(file.read_bytes()).hexdigest()==item['sha256'],item['path']
print(f'P8: {len(manifest["files"])} artifacts verified; original realtime/UI increment passed; full product NOT COMPLETE')
