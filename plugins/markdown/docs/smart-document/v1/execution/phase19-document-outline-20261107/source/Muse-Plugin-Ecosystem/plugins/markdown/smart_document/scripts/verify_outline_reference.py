#!/usr/bin/env python3
"""Verify immutable SiYuan/AppFlowy outline references and runtime reuse anchors."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
V=ROOT/'vendor/outline_reference'
entries=json.loads((V/'upstream-files.json').read_text())
assert len(entries)==6
pins={'siyuan':'d3af9d5782082b379d45a69eedf4ebcfe8ba6889','appflowy':'17e24f8232488fdac1213b17445af7dd4fb07ad2'}
for item in entries:
 assert item['revision']==pins[item['path'].split('/')[1]]
 b=(V/item['path']).read_bytes()
 assert hashlib.sha256(b).hexdigest()==item['sha256']
 assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==item['gitBlob']
assert 'doc.get_plain_text_from_block(&id)' in (ROOT/'rust/src/outline.rs').read_text()
assert 'EditorScrollController(editorState: document.editor)' in (ROOT/'flutter/lib/src/outline_view.dart').read_text()
assert 'document.editor.showHeader ? 1 : 0' in (ROOT/'flutter/lib/src/outline_view.dart').read_text()
print('Outline: six pinned reference files, original kernel text extraction and editor scroll controller verified')
