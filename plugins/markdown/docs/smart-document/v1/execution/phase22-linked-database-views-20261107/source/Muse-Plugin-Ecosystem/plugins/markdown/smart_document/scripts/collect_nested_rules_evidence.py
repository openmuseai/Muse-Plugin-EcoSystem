#!/usr/bin/env python3
"""Freeze P17 original nested shared rules evidence."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase17-nested-rules-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='nested-rule-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/nested-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-nested-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(7,3)
  for name in ['result.json','nested-e2e.json','nested-reopen.json','nested-editor.png','nested-local-branch.png','nested-merged.png','nested_view_document_test.dart.log','nested_view_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p17-core-final.log','p17-dataset-full.log','p17-dataset-analysis.log','p17-example-analysis.log','p17-web-analysis.log','p17-web-build.log','p17-wasm-build.log','p17-view-rules-vendor.log','p17-yrs-vendor.log','p17-native-web-readback.log','p17-browser-build-hashes.json','dataset-wasm-artifacts.json','nested-web-public.json','nested-web-result.json','nested-web-peer.json','nested-web-reload.json','nested-native-web-readback.json','nested-web-dialog.ax.txt','nested-web-dialog.png','nested-web-alice-split.ax.txt','nested-web-alice-split.png','nested-web-bob-split.ax.txt','nested-web-bob-split.png','nested-web-merged.ax.txt','nested-web-merged.png','nested-web-undo.ax.txt','nested-web-redo.ax.txt','nested-web-final.ax.txt','nested-web-final.png','nested-web-peer.ax.txt','nested-web-peer.png','nested-web-reload.ax.txt','nested-web-reload.png']
 for name in names:copy(ROOT/'.build'/name,name)
 copy(ROOT/'.build/p17-nested-before.log','diagnostic/original-atomic-children-lost-independent-intent.log')
 for name in ['muse_dataset_core.js','muse_dataset_core_bg.wasm']:copy(ROOT/'dataset/flutter/assets/wasm'/name,'runtime-artifacts/'+name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','scripts/verify_dates_evidence.py','scripts/verify_lifecycle_evidence.py','scripts/verify_view_rules_evidence.py','scripts/verify_concurrent_views_evidence.py','40-PHASE17-NESTED-SHARED-RULES.zh-CN.md','scripts/verify_date_filter_evidence.py','scripts/verify_nested_rules_evidence.py'])
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst'})
 for vendor in ['appflowy_view_rules','yrs']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source and fixed original filter/seed extraction snapshot; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)} for f in owned]},indent=2)+'\n')
 binary=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text());assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==binary['sha256'];(stage/'cloud-binary.json').write_text(json.dumps({**binary,'source':'P8 binary unchanged; P14 loopback CORS 50946 reused'},indent=2)+'\n')
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout;(stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 report={'phase':'P17-20261107','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun','slices':{'datasetCoreChecks':50,'datasetFullPackageTests':51,'appleUiChecksPerPlatform':7,'appleFreshProcessChecksPerPlatform':3,'webUiChecks':8,'webPeerChecks':7,'webReloadChecks':5,'nativeWebReadbackChecks':4},'limits':['Seven basic fields and one editable Grid; full 18 fields/5 views, relative date clocks, date unequal shortcut, Chinese collation, grouping/calculation and source-block binding remain open','Original filter seed is best effort, not a general nested or negative constraint solver; text cells remain key/value CRDTs','New shared nested child intents are qualified; legacy migration, old writer negotiation, same-ID creation, concurrent shape changes and complete collaborative history remain open','Durable ACK, distributed immediate revoke, Host registry/session pooling/inherited grants, UID multi-device roster and scoped subscription remain open','Physical IME/soft-keyboard geometry, Android, comments/history/Agent/Office and full editing parity remain open'],'fullParityGate':{'status':'rejected-expected','exitCode':1}}
 (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P17: nested original shared rules\n\nOriginal atomic-children intent-loss reproduction retained. Shared Array/Map children retain stable identities; legacy child mutation is explicitly refused before mutation. Core 50 and full Dataset package 51 pass. macOS/iOS each 7 UI + 3 fresh-process. Web 8, peer 7, offline 5, Native real-Cloud readback 4. Full product NOT COMPLETE; Android unrun.\n\n![Nested UI](nested-web-dialog.png)\n![Alice branch](nested-web-alice-split.png)\n![Bob branch](nested-web-bob-split.png)\n![Merged children](nested-web-merged.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');stage.rename(dest)
 print(f'P17 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
