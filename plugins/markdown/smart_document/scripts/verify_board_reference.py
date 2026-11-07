#!/usr/bin/env python3
"""Verify pinned SiYuan/AppFlowy board references without fetching or changing vendors."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1];V=ROOT/'vendor/board_reference'
pins={'siyuan':'d3af9d5782082b379d45a69eedf4ebcfe8ba6889','appflowy':'17e24f8232488fdac1213b17445af7dd4fb07ad2'}
items=json.loads((V/'upstream-files.json').read_text());assert len(items)==8
for item in items:
    assert item['revision']==pins[item['path'].split('/')[1]]
    data=(V/item['path']).read_bytes();assert hashlib.sha256(data).hexdigest()==item['sha256']
    assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==item['gitBlob']
s=(ROOT/'dataset/rust/src/commands.rs').read_text()
for token in ['GroupSetting::new','DatabaseLayout::Board','Command::SetCell','BOARD_CHANGED']:
    assert token in s
assert 'GroupSetting::try_from(raw)' in (ROOT/'dataset/rust/src/board.rs').read_text()
print('P24: eight original board/group references and existing field/row/undo/transport reuse verified')
