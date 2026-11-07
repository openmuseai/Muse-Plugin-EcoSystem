#!/usr/bin/env python3
"""Freeze P19 outline and original GC deletion-tail repair evidence without secrets."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1';CLOUD=WORKSPACE/'Muse-Server/AppFlowy-Cloud'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase19-document-outline-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='outline-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt','.html'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/outline-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-outline-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(8,3)
  for name in ['result.json','outline-e2e.json','outline-reopen.json','outline-panel.png','outline-navigation.png','outline_document_test.dart.log','outline_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p19-core-tests-qualified.log','p19-dataset-core-tests.log','p19-yrs-complete-suite.log','p19-yrs-fixtures.json','p19-yrs-vendor.log','p19-cloud-yrs-vendor.log','p19-editor-vendor.log','p19-outline-reference.log','p19-cloud-build.log','p19-cloud-binary.json','p19-cloud-restart.log','p19-document-selected-fixed.log','p19-document-cloud-isolated.log','p19-dataset-full-fixed.log','p19-dataset-sdk-tests.log','p19-document-analysis-final.log','p19-example-analysis-final.log','p19-dataset-analysis-final.log','p19-web-analysis-fixed.log','p19-web-build-fixed.log','p19-document-wasm-fixed-build.log','p19-dataset-wasm-fixed-build.log','p19-native-web-readback.log','p19-browser-build-hashes.json','p19-frozen-baselines.json','p19-frozen-baselines.log','wasm-artifacts.json','dataset-wasm-artifacts.json','realtime-wasm-artifacts.json','outline-web-public.json','outline-web-result.json','outline-web-peer.json','outline-web-reload.json','outline-native-web-readback.json','outline-web-collapsed.ax.txt','outline-web-collapsed.png','outline-web-navigation.ax.txt','outline-web-navigation.png','outline-web-deletion.ax.txt','outline-web-deletion.png','outline-web-final.ax.txt','outline-web-final.png','outline-web-reload.ax.txt','outline-web-reload.png']
 for name in names:copy(ROOT/'.build'/name,name)
 diagnostic=['p19-web-first-unqualified.json','p19-unqualified-browser-alice.ax.txt','p19-unqualified-browser-bob.ax.txt','p19-unqualified-browser-alice.png','p19-captured-delete-first.log','p19-captured-delete-fixed.log','p19-yrs-all-tests.log','p19-live-browser-bob-after-rename.json','p19-live-browser-bob.json','p19-browser-native-bob.json','p19-live-cloud-diagnostic.json','p19_live_diagnostic_test.dart','p19-cloud-lock.log']
 for name in diagnostic:copy(ROOT/'.build'/name,'diagnostic/'+name)
 copy(ROOT/'.build/outline-runs/20261106T202625Z-outline-b20de3572830/outline_document_test.dart.log','diagnostic/native-frame-readiness.log')
 for base,domain in [(ROOT/'flutter/assets/wasm','document'),(ROOT/'dataset/flutter/assets/wasm','dataset'),(WORKSPACE/'Muse-Client/packages/muse_appflowy_realtime/assets/wasm','realtime')]:
  for artifact in base.iterdir():
   if artifact.is_file() and artifact.suffix in {'.js','.wasm'}:copy(artifact,'runtime-artifacts/'+domain+'/'+artifact.name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','40-PHASE17-NESTED-SHARED-RULES.zh-CN.md','41-PHASE18-USER-PRESENCE-ROSTER.zh-CN.md','42-PHASE19-DOCUMENT-OUTLINE.zh-CN.md','outline-functional-review/index.html'])
 owned.update((DOCS/'scripts').glob('verify*evidence.py'))
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets','rust/fixtures']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst','.json'})
 for vendor in ['appflowy_view_rules','yrs','outline_reference']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned.update(f for f in (CLOUD/'vendor/yrs').rglob('*') if f.is_file())
 owned.update(CLOUD/name for name in ['Cargo.toml','Cargo.lock'])
 fixtures=json.loads((ROOT/'.build/p19-yrs-fixtures.json').read_text())
 owned.update(ROOT/'.build/yrs-test-workspace'/e['path'] for e in fixtures['files'])
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source, fixed upstream references and test inputs; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]},indent=2)+'\n')
 binary=json.loads((ROOT/'.build/p19-cloud-binary.json').read_text());assert sha(CLOUD/'target/debug/appflowy_cloud')==binary['sha256']
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout
 (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 (stage/'result.json').write_text(json.dumps({'phase':'P19-20261107','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun','slices':{'documentRustTests':27,'datasetRustTests':50,'originalYrsLibraryPassed':305,'originalYrsLibraryIgnored':1,'documentSelectedTests':46,'isolatedCloudRestartTests':1,'datasetFullTests':51,'datasetSdkTests':3,'appleUiChecksPerPlatform':8,'appleFreshProcessChecksPerPlatform':3,'webUiChecks':8,'webPeerChecks':5,'webReloadChecks':4,'nativeWebReadbackChecks':4},'limits':['Outline child collapse is local view state; body folding/focus/persistent preferences remain open','Full SiYuan editing, complete database fields/views and full collaboration remain open','Same original Yrs version and wire encoding; mixed old-parser deployments lack capability negotiation','Historical deletion effects already discarded by an old parser are not claimed automatically recoverable','Android, Windows/Linux and physical IME remain unqualified','Durable ACK/outbox, distributed immediate revoke, full sharing/comments/history/Agent/Office remain open'],'fullParityGate':{'status':'rejected-expected','exitCode':1}},indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P19：协作正文目录与原删除尾部修复\n\nDocument Rust 27、Dataset Rust 50；原 Yrs 完整库 305 通过 / 1 沿用上游 ignored；Document 46 + 独立 Cloud 重启 1、Dataset 51、公共 Dataset SDK 3。macOS/iOS 各 8 UI + 3 重开；Web 8、Bob 5、离线 4、Native Cloud 读回 4。\n\n固定原 AppFlowy/SiYuan 参考，保持原协议；Cloud 本轮重新构建，含同一 GC 删除尾部修复。早期失败保存在 diagnostic，不计作通过。应用 JS 与测试身份不复制进证据。完整产品 NOT COMPLETE，Android 未运行。\n\n![Desktop](macos/outline-panel.png)\n![Mobile](ios/outline-panel.png)\n![Web](outline-web-final.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 subprocess.run(['python3',str(DOCS/'scripts/verify_outline_evidence.py'),'--root',str(stage),'--source'],check=True)
 stage.rename(dest);print(f'P19 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
