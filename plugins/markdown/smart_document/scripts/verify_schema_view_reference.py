#!/usr/bin/env python3
"""Verify original global schema versus view-order references and runtime reuse."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1];V=ROOT/'vendor/schema_view_reference'
pins={'siyuan':'d3af9d5782082b379d45a69eedf4ebcfe8ba6889','appflowy-collab':'e59260e524f33104b0ddcd6bb8f6218cad0f7e18'}
items=json.loads((V/'upstream-files.json').read_text());assert len(items)==6
for item in items:
    assert item['revision']==pins[item['path'].split('/')[1]]
    data=(V/item['path']).read_bytes();assert hashlib.sha256(data).hexdigest()==item['sha256']
    assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==item['gitBlob']
assert 'database.get_fields(None)' in ''.join((ROOT/'dataset/rust/src/views.rs').read_text().split())
assert 'crate::views::fields(&self.database, &view)?' in (ROOT/'dataset/rust/src/commands.rs').read_text()
assert 'crate::views::fields(&self.database, view)?' in (ROOT/'dataset/rust/src/session.rs').read_text()
print('P23: six fixed original schema/view references and shared original FieldMap projection verified')
