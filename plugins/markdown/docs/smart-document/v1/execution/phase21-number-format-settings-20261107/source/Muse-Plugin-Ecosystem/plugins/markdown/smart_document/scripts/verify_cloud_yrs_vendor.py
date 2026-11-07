#!/usr/bin/env python3
"""Verify server's independent original Yrs package and the identical GC fix."""
from pathlib import Path
import hashlib,json,subprocess,tempfile,shutil
ROOT=Path(__file__).resolve().parents[1];CLOUD=ROOT.parents[3]/'Muse-Server/AppFlowy-Cloud';V=CLOUD/'vendor/yrs'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 pin=json.loads((V/'openmuse-upstream.json').read_text());entries=json.loads((V/'upstream-files.json').read_text())
 assert pin['version']=='0.23.5' and pin['registryPackageChecksum']=='197c2b4b298f35c3ba4d549884ac872a961112095b29f173ab45e3d5cf609018'
 changed={p['file']:p['sha256']for p in pin['patches']};assert set(changed)=={'src/transaction.rs'} and len(entries)==64
 for entry in entries:assert sha(V/entry['path'])==changed.get(entry['path'],entry['sha256']),entry['path']
 assert sha(V/'src/transaction.rs')==sha(ROOT/'vendor/yrs/src/transaction.rs')
 assert sha(V/'openmuse.patch')==pin['patchSha256']
 with tempfile.TemporaryDirectory(prefix='muse-cloud-yrs-') as folder:
  target=Path(folder);(target/'src').mkdir();shutil.copy2(V/'src/transaction.rs',target/'src/transaction.rs')
  subprocess.run(['git','apply','--reverse',str(V/'openmuse.patch')],cwd=target,check=True,capture_output=True)
  assert sha(target/'src/transaction.rs')==next(e['sha256']for e in entries if e['path']=='src/transaction.rs')
 print('Cloud Yrs: 64 pinned originals, one reversible GC deletion-tail patch identical to client; original undo APIs and wire encoding retained')
if __name__=='__main__':main()
