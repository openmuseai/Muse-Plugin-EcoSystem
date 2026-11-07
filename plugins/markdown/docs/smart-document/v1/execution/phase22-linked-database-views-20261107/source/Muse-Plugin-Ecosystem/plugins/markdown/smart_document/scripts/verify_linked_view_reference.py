#!/usr/bin/env python3
"""Validate original view references and original linked-view command reuse."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
V=ROOT/'vendor/linked_view_reference'
pins={'siyuan':'d3af9d5782082b379d45a69eedf4ebcfe8ba6889','appflowy':'17e24f8232488fdac1213b17445af7dd4fb07ad2'}
entries=json.loads((V/'upstream-files.json').read_text())
assert len(entries)==6
for item in entries:
    assert item['revision']==pins[item['path'].split('/')[1]]
    data=(V/item['path']).read_bytes()
    assert hashlib.sha256(data).hexdigest()==item['sha256']
    assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==item['gitBlob']
assert 'self.database.create_linked_view(' in (ROOT/'dataset/rust/src/commands.rs').read_text()
assert 'get_inline_view_id(&database.collab)' in (ROOT/'dataset/rust/src/views.rs').read_text()
print('P22: six original SiYuan/AppFlowy references and original linked-view/inline membership reuse verified')
