#!/usr/bin/env python3
"""Freeze P16 original date filters, original seed decisions and record editor evidence."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase16-date-filters-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='date-filter-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/date_filter-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-date_filter-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(8,3)
  for name in ['result.json','date_filter-e2e.json','date_filter-reopen.json','date_filter-editor.png','date_filter-dialog.png','date_filter-conflict.png','date_filter-calendar.png','date_filter-record.png','date_filter_document_test.dart.log','date_filter_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p16-core-final.log','p16-original-filters-final.log','p16-dataset-full-final.log','p16-date-filter-ui-tests.log','p16-dataset-analysis-qualified.log','p16-example-analysis.log','p16-web-analysis-2.log','p16-date-filter-web-build.log','p16-wasm-build.log','p16-view-rules-vendor.log','p16-yrs-vendor.log','p16-native-web-readback-qualified.log','p16-browser-build-hashes.json','p16-browser-diagnostics.json','dataset-wasm-artifacts.json','date_filter-web-public.json','date_filter-web-result.json','date_filter-web-peer.json','date_filter-web-reload.json','date_filter-native-web-readback.json','date_filter-web-live.ax.txt','date_filter-web-live.png','date_filter-web-history.ax.txt','date_filter-web-final.ax.txt','date_filter-web-final.png','date_filter-web-peer.ax.txt','date_filter-web-peer.png','date_filter-web-reload.ax.txt','date_filter-web-reload.png','dataset-cloud-result.json','dataset-choice-cloud-result.json','dataset-cloud-deletion-result.json','dataset-realtime-cloud-result.json','dataset-realtime-permissions-result.json']
 for name in names:copy(ROOT/'.build'/name,name)
 copy(ROOT/'.build/p16-native-web-readback-first-timeout.log','diagnostic/native-readback-default-timeout.log')
 for name in ['muse_dataset_core.js','muse_dataset_core_bg.wasm']:copy(ROOT/'dataset/flutter/assets/wasm'/name,'runtime-artifacts/'+name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','scripts/verify_dates_evidence.py','scripts/verify_lifecycle_evidence.py','scripts/verify_view_rules_evidence.py','scripts/verify_concurrent_views_evidence.py','scripts/verify_date_filter_evidence.py'])
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst'})
 for vendor in ['appflowy_view_rules','yrs']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source and fixed original filter/seed extraction snapshot; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)} for f in owned]},indent=2)+'\n')
 binary=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text());assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==binary['sha256'];(stage/'cloud-binary.json').write_text(json.dumps({**binary,'source':'P8 binary unchanged; P14 loopback CORS 50946 reused'},indent=2)+'\n')
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout;(stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 report={'phase':'P16-20261107','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun','slices':{'originalFilterTests':21,'datasetCoreChecks':44,'datasetFullPackageTests':51,'appleUiChecksPerPlatform':8,'appleFreshProcessChecksPerPlatform':3,'webUiChecks':8,'webPeerChecks':7,'webReloadChecks':7,'nativeWebReadbackChecks':4},'limits':['Seven basic fields and one editable Grid; full 18 fields/5 views, relative date clocks, date unequal shortcut, Chinese collation, grouping/calculation and source-block binding remain open','Original filter seed is best effort, not a general nested or negative constraint solver; text cells remain key/value CRDTs','Nested-child intent merge, same-ID concurrent creation, migration and complete collaborative history remain open','Durable ACK, distributed immediate revoke, Host registry/session pooling/inherited grants, UID multi-device roster and scoped subscription remain open','Physical IME/soft-keyboard geometry, Android, comments/history/Agent/Office and full editing parity remain open'],'fullParityGate':{'status':'rejected-expected','exitCode':1}}
 (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P16: original date rules, seed decisions and hidden record editor\n\nSee the linked P16 design addendum for product scope and Chinese interaction specification. Original filter tests: 21; core: 44; complete Dataset package: 51. macOS/iOS: 8 UI + 3 fresh-process each. Web: 8 / peer 7 / offline 7; Native real-Cloud readback: 4.\n\nWorking source snapshots and fixed upstream extraction are fingerprinted. Application JS containing synthetic credentials is represented only by a digest. Diagnostic timeout and automation reflow are not passes. Full product remains NOT COMPLETE; Android unrun.\n\n![iOS record editor](ios/date_filter-record.png)\n![iOS date filter](ios/date_filter-dialog.png)\n![Web final](date_filter-web-final.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');stage.rename(dest)
 print(f'P16 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
