#!/usr/bin/env python3
"""Record the tested browser build; archive only pure runtime bytes, never credential-bearing app JS."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1];build=ROOT/'flutter/web_example/build/board-web'
items=[]
for domain,package,report in [('document','openmuse_smart_document','wasm-artifacts.json'),('dataset','openmuse_dataset','dataset-wasm-artifacts.json'),('realtime','muse_appflowy_realtime','realtime-wasm-artifacts.json')]:
    expected={x['file']:x['sha256'] for x in json.loads((ROOT/'.build'/report).read_text())['artifacts']}
    base=build/'assets/packages'/package/'assets/wasm'
    for name,digest in expected.items():
        f=base/name;actual=hashlib.sha256(f.read_bytes()).hexdigest();assert actual==digest,(domain,name)
        items.append({'domain':domain,'file':name,'sha256':actual,'bytes':f.stat().st_size,'archivedBytes':True})
f=build/'main.dart.js';items.append({'domain':'application','file':f.name,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'bytes':f.stat().st_size,'archivedBytes':False})
assert len(items)==7
(ROOT/'.build/p24-browser-build-hashes.json').write_text(json.dumps({'allRuntimeArtifactsMatchReports':True,'files':items},indent=2)+'\n')
print('P24 browser: six pure runtime artifacts match reports; application JS recorded by hash only')
