#!/usr/bin/env python3
"""One-time extraction of checksum-pinned Yrs with an optional bounded pop API."""
from pathlib import Path,PurePosixPath
import difflib,hashlib,json,tarfile
ROOT=Path(__file__).resolve().parents[1]
CHECKSUM='197c2b4b298f35c3ba4d549884ac872a961112095b29f173ab45e3d5cf609018'
def main():
 archives=list((Path.home()/'.cargo/registry/cache').glob('*/yrs-0.23.5.crate'));assert len(archives)==1
 package=archives[0];assert hashlib.sha256(package.read_bytes()).hexdigest()==CHECKSUM
 v=ROOT/'vendor/yrs';assert not v.exists() or not any(v.iterdir());v.mkdir(exist_ok=True)
 manifest=[]
 with tarfile.open(package,'r:gz') as archive:
  for member in archive.getmembers():
   path=PurePosixPath(member.name);assert path.parts[0]=='yrs-0.23.5' and '..' not in path.parts
   if member.isdir():continue
   assert member.isfile();rel=Path(*path.parts[1:]);p=v/rel;assert p.resolve().is_relative_to(v.resolve())
   data=archive.extractfile(member).read();p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
   manifest.append({'path':str(rel),'sha256':hashlib.sha256(data).hexdigest()})
 p=v/'src/undo.rs';before=p.read_text();s=before
 s=s.replace('Self::undo_inner(inner, txn, origin)','Self::undo_inner(inner, txn, origin, usize::MAX)').replace('Self::redo_inner(inner, txn, origin)','Self::redo_inner(inner, txn, origin, usize::MAX)')
 for name in ['undo','redo']:
  old=f'fn {name}_inner(inner: &mut Inner<M>, mut txn: TransactionMut, origin: Origin) -> bool {{'
  assert old in s;s=s.replace(old,f'fn {name}_inner(inner: &mut Inner<M>, mut txn: TransactionMut, origin: Origin, max_items: usize) -> bool {{')
 assert s.count('            &inner.scope,\n        );')==2;s=s.replace('            &inner.scope,\n        );','            &inner.scope,\n            max_items,\n        );')
 s=s.replace('        scope: &HashSet<BranchPtr>,\n    ) -> Option<StackItem<M>> {','        scope: &HashSet<BranchPtr>,\n        max_items: usize,\n    ) -> Option<StackItem<M>> {')
 assert s.count('        while let Some(item) = stack.pop() {')==1
 s=s.replace('        while let Some(item) = stack.pop() {','        let mut remaining = max_items;\n        while remaining > 0 {\n            let Some(item) = stack.pop() else { break };\n            remaining -= 1;')
 for name in ['undo','redo']:
  needle=f'    fn {name}_inner(';i=s.index(needle)
  s=s[:i]+f'''    /// {name.title()} at most one captured stack item, including an obsolete item.
    /// Original inversion is unchanged; do not cross application command boundaries.
    pub fn {name}_one_blocking(&mut self) -> bool {{
        let origin = self.as_origin();
        let inner = Arc::get_mut(&mut self.state).unwrap();
        let txn = self.doc.transact_mut_with(origin.clone());
        Self::{name}_inner(inner, txn, origin, 1)
    }}

'''+s[i:]
 p.write_text(s)
 (v/'openmuse.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),s.splitlines(True),fromfile='a/src/undo.rs',tofile='b/src/undo.rs')))
 (v/'upstream-files.json').write_text(json.dumps(manifest,indent=2)+'\n')
 (v/'openmuse-upstream.json').write_text(json.dumps({'repository':'https://github.com/y-crdt/y-crdt','version':'0.23.5','registryPackageChecksum':CHECKSUM,'license':'MIT','patches':[{'file':'src/undo.rs','sha256':hashlib.sha256(p.read_bytes()).hexdigest()}],'patchSha256':hashlib.sha256((v/'openmuse.patch').read_bytes()).hexdigest(),'scope':'Dataset history only: optional one captured item pop. Original default methods, inversion, structs and wire codec unchanged'},indent=2)+'\n')
 print(f'Yrs 0.23.5: {len(manifest)} original files from checksum-verified registry archive; one controlled optional-API patch')
if __name__=='__main__':main()
