#!/usr/bin/env python3
"""Verify pinned original numeric model/editor references and existing codec reuse."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1];V=ROOT/'vendor/number_reference'
entries=json.loads((V/'upstream-files.json').read_text());assert len(entries)==8
pins={'siyuan':'d3af9d5782082b379d45a69eedf4ebcfe8ba6889','appflowy':'17e24f8232488fdac1213b17445af7dd4fb07ad2'}
for item in entries:
 assert item['revision']==pins[item['path'].split('/')[1]]
 b=(V/item['path']).read_bytes();assert hashlib.sha256(b).hexdigest()==item['sha256']
 assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==item['gitBlob']
s=(ROOT/'dataset/rust/src/numbers.rs').read_text();assert 'NumberCellData::from(cell)'in s and 'Decimal::from_str_exact'in s
assert 'writer.convert_json_to_cell(numbers::writer_value(value)?)'in(ROOT/'dataset/rust/src/model.rs').read_text()
print('Numbers: eight pinned references; original NumberCellData/type-option codecs and exact decimal boundary verified')
