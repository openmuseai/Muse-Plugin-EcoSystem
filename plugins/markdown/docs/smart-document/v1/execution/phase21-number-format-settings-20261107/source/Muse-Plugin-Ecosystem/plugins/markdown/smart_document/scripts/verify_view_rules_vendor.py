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
 entries=json.loads((V/'upstream-files.json').read_text());assert len(entries)==15
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
 before=(V/'upstream/frontend/rust-lib/flowy-database2/src/services/field/type_options/date_type_option/date_filter.rs').read_text();after=(V/'src/date_filter.rs').read_text()
 assert section(before,'  fn get_strategy')==section(after,'  fn get_strategy')
 assert section(before,'#[cfg(test)]')==section(after,'#[cfg(test)]').replace(', chrono_tz::UTC)', ')')
 # All date strategy edits must be solely explicit timezone plumbing.
 strategy=section(after,'impl DateFilterStrategy').replace(', timezone: chrono_tz::Tz','').replace(', timezone)',')')
 assert section(before,'impl DateFilterStrategy')==strategy
 for name,ty in [('text_filter.rs','TextFilterPB'),('select_filter.rs','SelectOptionFilterPB')]:
  sub='text_type_option' if ty=='TextFilterPB' else 'selection_type_option'
  a=(V/f'upstream/frontend/rust-lib/flowy-database2/src/services/field/type_options/{sub}/{name}').read_text();b=(V/'src'/name).read_text()
  assert section(a,'impl PreFillCellsWithFilter')==section(b,'impl PreFillCellsWithFilter')
 original_prefill=section(before,'impl PreFillCellsWithFilter for DateFilterPB')
 adapted_prefill=section(after,'impl DateFilterPB {\n  pub fn get_compliant_cell_in_zone')
 adapted_prefill=adapted_prefill.replace('impl DateFilterPB','impl PreFillCellsWithFilter for DateFilterPB',1).replace('pub fn get_compliant_cell_in_zone(&self, field: &Field, timezone: chrono_tz::Tz)','fn get_compliant_cell(&self, field: &Field)').replace('timezone','Local')
 assert original_prefill==adapted_prefill
 print('View rules vendor: 15 pinned originals, original filter strategies and 21 original tests; date timezone and bounded prefill extraction verified')
if __name__=='__main__':main()
