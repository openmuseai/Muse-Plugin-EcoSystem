#!/usr/bin/env python3
"""Verify checksum-pinned original Yrs files and reversible single-source patch."""
from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1];V=ROOT/'vendor/yrs'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 pin=json.loads((V/'openmuse-upstream.json').read_text());assert pin['version']=='0.23.5' and pin['registryPackageChecksum']=='197c2b4b298f35c3ba4d549884ac872a961112095b29f173ab45e3d5cf609018'
 entries=json.loads((V/'upstream-files.json').read_text());assert len(entries)==64
 changed={entry['file']:entry['sha256']for entry in pin['patches']};assert set(changed)=={'src/undo.rs'}
 assert sha(V/'openmuse.patch')==pin['patchSha256']
 for item in entries:
  p=V/item['path'];assert p.resolve().is_relative_to(V.resolve()) and p.is_file() and not p.is_symlink()
  assert sha(p)==changed.get(item['path'],item['sha256']),item['path']
 original=next(e['sha256']for e in entries if e['path']=='src/undo.rs');assert sha(V/'upstream/src/undo.rs')==original
 with tempfile.TemporaryDirectory(prefix='muse-yrs-patch-check-') as folder:
  temp=Path(folder);(temp/'src').mkdir();shutil.copy2(V/'src/undo.rs',temp/'src/undo.rs')
  subprocess.run(['git','apply','--reverse',str(V/'openmuse.patch')],cwd=temp,check=True,capture_output=True)
  assert sha(temp/'src/undo.rs')==original
 print('Yrs vendor: 64 pinned original files; one reversible optional bounded-undo API patch; all wire/struct/merge sources unchanged')
if __name__=='__main__':main()
