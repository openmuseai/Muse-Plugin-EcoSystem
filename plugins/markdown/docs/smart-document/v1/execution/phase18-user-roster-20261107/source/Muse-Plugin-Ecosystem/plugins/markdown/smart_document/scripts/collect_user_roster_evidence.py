#!/usr/bin/env python3
"""Freeze P18 authenticated multi-position user roster evidence."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase18-user-roster-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='user-roster-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/users-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-users-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(8,3)
  for name in ['result.json','users-e2e.json','users-reopen.json','users-editor.png','users-dataset-roster.png','users-document-roster.png','user_presence_document_test.dart.log','user_presence_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p18-profile-core-tests.log','p18-contract-analysis.log','p18-contract-tests.log','p18-realtime-analysis-qualified.log','p18-realtime-tests-fourth.log','p18-widgets-analysis-qualified.log','p18-widgets-tests-qualified.log','p18-dataset-analysis-qualified.log','p18-dataset-full-qualified.log','p18-document-analysis-qualified.log','p18-document-selected-qualified.log','p18-document-cloud-isolated.log','p18-example-analysis-qualified.log','p18-web-analysis-second.log','p18-web-build.log','p18-realtime-wasm-build.log','p18-view-rules-vendor.log','p18-yrs-vendor.log','p18-native-web-readback.log','p18-browser-build-hashes.json','p18-profile-cors.json','p18-test-scheduling-diagnostic.json','wasm-artifacts.json','dataset-wasm-artifacts.json','realtime-wasm-artifacts.json','users-web-public.json','users-web-result.json','users-web-peer-primary.json','users-web-peer-two.json','users-web-self-other.json','users-web-reload.json','users-native-web-readback.json','users-web-four-positions.ax.txt','users-web-four-positions.png','users-web-dataset-roster.ax.txt','users-web-dataset-roster.png','users-web-one-peer-left.ax.txt','users-web-one-peer-left.png','users-web-own-other-only.ax.txt','users-web-own-other-only.png','users-web-local-only.ax.txt','users-web-document-roster.ax.txt','users-web-document-roster.png','users-web-final.ax.txt','users-web-final.png','users-web-reload.ax.txt','users-web-reload.png']
 for name in names:copy(ROOT/'.build'/name,name)
 for name in ['p18-dataset-full-first.log','p18-document-full-first.log']:copy(ROOT/'.build'/name,'diagnostic/'+name)
 for base,domain in [(ROOT/'flutter/assets/wasm','document'),(ROOT/'dataset/flutter/assets/wasm','dataset'),(WORKSPACE/'Muse-Client/packages/muse_appflowy_realtime/assets/wasm','realtime')]:
  for artifact in base.iterdir():
   if artifact.is_file() and artifact.suffix in {'.js','.wasm'}:copy(artifact,'runtime-artifacts/'+domain+'/'+artifact.name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','scripts/verify_dates_evidence.py','scripts/verify_lifecycle_evidence.py','scripts/verify_view_rules_evidence.py','scripts/verify_concurrent_views_evidence.py','40-PHASE17-NESTED-SHARED-RULES.zh-CN.md','scripts/verify_date_filter_evidence.py','41-PHASE18-USER-PRESENCE-ROSTER.zh-CN.md','scripts/verify_nested_rules_evidence.py','scripts/verify_user_roster_evidence.py'])
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst'})
 for vendor in ['appflowy_view_rules','yrs']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source and fixed original filter/seed extraction snapshot; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)} for f in owned]},indent=2)+'\n')
 binary=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text());assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==binary['sha256'];(stage/'cloud-binary.json').write_text(json.dumps({**binary,'source':'P8 binary unchanged; P14 loopback CORS 50946 reused'},indent=2)+'\n')
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout;(stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 report={'phase':'P18-20261107','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun','slices':{'realtimeRustChecks':6,'neutralContractTests':5,'sharedWidgetsTests':5,'realtimePackageTests':4,'datasetFullPackageTests':51,'documentSelectedTests':43,'documentIsolatedCloudLifecycleTests':1,'appleUiChecksPerPlatform':8,'appleFreshProcessChecksPerPlatform':3,'webUiChecks':20,'webPeerChecksPerPosition':5,'webPeerPositions':3,'webReloadChecks':4,'nativeWebReadbackChecks':4},'limits':['User roster qualified with two users/four positions for Document and Dataset; large scale, Host directory/avatars, Office range and cross-instance failure cases remain open','Profile UID is transient and origin-bound; it is not a sharing ACL or inherited resource grant','Full SiYuan editing, 18 fields/5 views, source blocks, rich cell collaboration and model migration remain open','Durable ACK/outbox, distributed immediate revoke, public share, comments/history/Agent/Office remain open','Physical IME/soft-keyboard geometry, Android and Windows/Linux UI remain unqualified','Old browser file-picker media readback prerequisite unavailable in current fixture; not counted as passed in P18; frozen P6 evidence preserved'],'fullParityGate':{'status':'rejected-expected','exitCode':1}}
 (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P18: authenticated user roster and multiple live positions\n\nRust identity decoder 6; neutral contract 5; shared UI 5; realtime adapter 4. Dataset 51, selected Document 43 and isolated Cloud restart 1 pass. macOS/iOS each 8 UI + 3 fresh-process; browser primary 20, three other positions 5 each, offline 4, Native real-Cloud readback 4. Original Cloud binary remains unchanged.\n\nInitial concurrent restart failures and old manual browser-media prerequisite are retained as diagnostics, never passes. Profile/online state stays transient. Application JS with synthetic credentials is digest-only. Full product NOT COMPLETE; Android unrun.\n\n![iOS member sheet](ios/users-dataset-roster.png)\n![Four positions, two users](users-web-four-positions.png)\n![Live member sheet](users-web-dataset-roster.png)\n![Final 20 checks](users-web-final.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');stage.rename(dest)
 print(f'P18 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
