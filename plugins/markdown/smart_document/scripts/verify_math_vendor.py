#!/usr/bin/env python3
"""Reverse the single Flutter compatibility patch and verify every original package byte."""
from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1];V=ROOT/'vendor/flutter_math_fork';meta=json.loads((V/'openmuse-upstream.json').read_text());items=json.loads((V/'upstream-files.json').read_text())
assert meta['version']=='0.7.3' and len(items)==meta['files']==381 and len(meta['patches'])==1
assert hashlib.sha256((V/'upstream-package.tar.gz').read_bytes()).hexdigest()==meta['archiveSha256']=='284bab89b2fbf1bc3a0baf13d011c1dd324d004e35d177626b77f2fc056366ac'
expected={i['path'] for i in items};allowed={'openmuse-upstream.json','upstream-files.json','openmuse.patch','upstream-package.tar.gz','OPENMUSE.md'}
assert {str(p.relative_to(V)) for p in V.rglob('*') if p.is_file()}==expected|allowed
with tempfile.TemporaryDirectory(prefix='muse-math-reference-') as temporary:
    target=Path(temporary)
    for item in items:
        p=target/item['path'];p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(V/item['path'],p)
    subprocess.run(['patch','-R','-p1','-i',str(V/'openmuse.patch')],cwd=target,check=True,capture_output=True)
    for item in items:assert hashlib.sha256((target/item['path']).read_bytes()).hexdigest()==item['sha256'],item['path']
reference=ROOT/'vendor/math_reference';pins={'siyuan':'d3af9d5782082b379d45a69eedf4ebcfe8ba6889','appflowy':'17e24f8232488fdac1213b17445af7dd4fb07ad2'}
refs=json.loads((reference/'upstream-files.json').read_text());assert len(refs)==8
for item in refs:
    assert item['revision']==pins[item['path'].split('/')[1]]
    data=(reference/item['path']).read_bytes();assert hashlib.sha256(data).hexdigest()==item['sha256']
    assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==item['gitBlob']
print('P25: 381 original package files, original archive, one reversible compatibility patch and eight pinned formula references verified')
