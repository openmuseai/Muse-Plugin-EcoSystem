#!/usr/bin/env python3
"""Verify fixed upstream sources, pure method/test reuse and local extraction."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
V=ROOT/'vendor/appflowy_view_rules'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def section(s,start):
 begin=s.index(start);brace=s.index('{',begin);depth=0
 for n in range(brace,len(s)):
  depth+=(s[n]=='{')-(s[n]=='}')
  if depth==0:return s[begin:n+1]
 raise AssertionError('Unbalanced source')
def main():
 pin=json.loads((V/'openmuse-upstream.json').read_text());assert pin['revision']=='17e24f8232488fdac1213b17445af7dd4fb07ad2'
 entries=json.loads((V/'upstream-files.json').read_text());assert len(entries)==12
 for entry in entries:
  p=V/'upstream'/entry['path'];b=p.read_bytes();assert sha(p)==entry['sha256'],str(p)
  assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==entry['gitBlob']
 for e in json.loads((V/'compiled-files.json').read_text()):assert sha(V/e['path'])==e['sha256'],e['path']
 paths={'text_filter.rs':('text_type_option/text_filter.rs','impl TextFilterPB'), 'number_filter.rs':('number_type_option/number_filter.rs','impl NumberFilterPB'), 'select_filter.rs':('selection_type_option/select_filter.rs','impl SelectOptionFilterPB')}
 for name,(path,impl) in paths.items():
  before=(V/'upstream/frontend/rust-lib/flowy-database2/src/services/field/type_options'/path).read_text();after=(V/'src'/name).read_text()
  for part in [impl,'#[cfg(test)]']:
   assert section(before,part)==section(after,part),(name,part)
  if name!='text_filter.rs':
   strategy='impl '+('NumberFilterStrategy' if name=='number_filter.rs' else 'SelectOptionFilterStrategy')
   assert section(before,strategy)==section(after,strategy)
 print('View rules vendor: 12 pinned originals, three unchanged evaluators/strategies and 14 original tests; extraction fingerprints verified')
if __name__=='__main__':main()
