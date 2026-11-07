#!/usr/bin/env python3
"""Run the complete pinned original Yrs library suite with its original external fixtures."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,urllib.request
ROOT=Path(__file__).resolve().parents[1]
REV='3996e91df00acdb67334695944bc43f60627103f'
FILES={
 'assets/bench-input/medium-test-dataset.bin':'7952093810c4a94088663d752d95d069fae1a40e',
 'assets/bench-input/small-test-dataset.bin':'662663551f592179c9d7b6241037f7a0478184fc',
 'assets/editing-traces/sequential_traces/automerge-paper.json.gz':'aa7f67ec0b02d5b21e8aa16a62879fc98d8b2daf',
 'assets/editing-traces/sequential_traces/friendsforever_flat.json.gz':'b1a6aa42fa3910b4d1d7c027b28d89ff26256de6',
 'assets/editing-traces/sequential_traces/rustcode.json.gz':'c19ecfd71ef5587ad672dcf3c4cb61d12bbc2f5e',
 'assets/editing-traces/sequential_traces/seph-blog1.json.gz':'a826034b74245eba52940a738a70b29ab15d8ec7',
 'assets/editing-traces/sequential_traces/sveltecomponent.json.gz':'9ccb0933516f04832725bfee4d66a89aa4bab04b',
 'assets/editing-traces/README.md':'4c888e4f5515bba3bc1671b73a32670d0c14ad0b',
 'assets/editing-traces/sequential_traces/README.md':'aecb52b70396dc8058626c3c002bf4d6cdd48689',
}
def blob(b):return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
def main():
 work=ROOT/'.build/yrs-test-workspace';work.mkdir(exist_ok=True)
 for path,digest in FILES.items():
  target=work/path
  if target.exists():b=target.read_bytes()
  else:
   with urllib.request.urlopen(f'https://raw.githubusercontent.com/y-crdt/y-crdt/{REV}/{path}',timeout=60) as response:b=response.read(40*1024*1024)
   assert len(b)<40*1024*1024 and blob(b)==digest,path
   target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b)
  assert blob(b)==digest,path
 vendor=ROOT/'vendor/yrs';local=work/'yrs'
 shutil.copytree(vendor,local,dirs_exist_ok=True,ignore=shutil.ignore_patterns('target','.git'))
 files=[{'path':path,'gitBlob':digest,'bytes':(work/path).stat().st_size,'sha256':hashlib.sha256((work/path).read_bytes()).hexdigest()}for path,digest in FILES.items()]
 (ROOT/'.build/p19-yrs-fixtures.json').write_text(json.dumps({'revision':REV,'files':files},indent=2)+'\n')
 env=os.environ.copy();env['CMAKE']='/Users/mac/Library/Android/sdk/cmake/3.22.1/bin/cmake'
 with (ROOT/'.build/p19-yrs-complete-suite.log').open('w') as out:
  result=subprocess.run(['cargo','test','--manifest-path',str(local/'Cargo.toml'),'--target-dir',str(ROOT/'.build/yrs-original-test-target'),'--lib'],env=env,stdout=out,stderr=subprocess.STDOUT)
 print('Pinned Yrs complete suite exit:',result.returncode)
 raise SystemExit(result.returncode)
if __name__=='__main__':main()
