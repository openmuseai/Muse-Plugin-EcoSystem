#!/usr/bin/env python3
"""Freeze P22 original linked views, primary membership and local selection presence evidence without secrets."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1';CLOUD=WORKSPACE/'Muse-Server/AppFlowy-Cloud'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase22-linked-database-views-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='linked-view-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt','.html'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/linked-view-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-linked-view-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(9,3)
  for name in ['result.json','linked-view-e2e.json','linked-view-reopen.json','linked-view-concurrent.png','linked-view-stale-name.png','linked-view-missing.png','linked-view-editor.png','linked_view_document_test.dart.log','linked_view_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p22-core-final.log', 'p22-linked-view-widget-first.log', 'p22-selection-widget.log', 'p22-dataset-flutter-full.log', 'p22-dataset-sdk-tests.log', 'p22-dataset-analysis-final.log', 'p22-example-analysis-final.log', 'p22-web-presence-analysis.log', 'p22-web-presence-build.log', 'p22-dataset-wasm-final.log', 'p22-native-web-final-readback.log', 'p22-web-presence-prepare.log', 'p22-cloud-final-restart.log', 'p22-browser-build-hashes.json', 'p22-frozen-baselines.json', 'p22-frozen-baselines.log', 'p22-view-reference.log', 'p19-cloud-binary.json', 'wasm-artifacts.json', 'dataset-wasm-artifacts.json', 'realtime-wasm-artifacts.json', 'linked-view-web-public.json', 'linked-view-web-prepare.json', 'linked-view-web-result.json', 'linked-view-web-peer.json', 'linked-view-web-reload.json', 'linked-view-native-web-readback.json', 'linked-view-web-alice-branch.ax.txt', 'linked-view-web-alice-branch.png', 'linked-view-web-bob-branch.ax.txt', 'linked-view-web-bob-branch.png', 'linked-view-web-base.ax.txt', 'linked-view-web-base.png', 'linked-view-web-filter.ax.txt', 'linked-view-web-filter.png', 'linked-view-web-stale.ax.txt', 'linked-view-web-stale.png', 'linked-view-web-missing.ax.txt', 'linked-view-web-missing.png', 'linked-view-web-presence-before.ax.txt', 'linked-view-web-presence-before.png', 'linked-view-web-presence-cleared.ax.txt', 'linked-view-web-presence-cleared.png', 'linked-view-web-final.ax.txt', 'linked-view-web-final.png', 'linked-view-web-peer.ax.txt', 'linked-view-web-peer.png', 'linked-view-web-reload.ax.txt', 'linked-view-web-reload.png']
 for name in names:copy(ROOT/'.build'/name,name)
 copy(ROOT/'.build/p22-view-membership-before.log','diagnostic/original-view-membership-failure.log')
 copy(ROOT/'.build/p22-pre-presence-runs.json','diagnostic/pre-presence-runs.json')
 copy(ROOT/'.build/p22-before-presence-review/linked-view-web-result.json','diagnostic/before-presence/linked-view-web-result.json')
 copy(ROOT/'.build/p22-before-presence-review/linked-view-web-peer.json','diagnostic/before-presence/linked-view-web-peer.json')
 copy(ROOT/'.build/p22-before-presence-review/linked-view-web-reload.json','diagnostic/before-presence/linked-view-web-reload.json')
 copy(ROOT/'.build/p22-before-presence-review/linked-view-native-web-readback.json','diagnostic/before-presence/linked-view-native-web-readback.json')
 copy(ROOT/'.build/p22-before-presence-review/p22-browser-build-hashes.json','diagnostic/before-presence/p22-browser-build-hashes.json')
 copy(ROOT/'.build/linked-view-runs/20261106T213955Z-linked-view-731e80c75823/result.json','diagnostic/before-presence/macos/result.json')
 copy(ROOT/'.build/linked-view-runs/20261106T213955Z-linked-view-731e80c75823/linked_view_document_test.dart.log','diagnostic/before-presence/macos/linked_view_document_test.dart.log')
 copy(ROOT/'.build/linked-view-runs/20261106T213955Z-linked-view-731e80c75823/linked_view_reopen_test.dart.log','diagnostic/before-presence/macos/linked_view_reopen_test.dart.log')
 copy(ROOT/'.build/linked-view-runs/20261106T214127Z-linked-view-dfccd81746af/result.json','diagnostic/before-presence/ios/result.json')
 copy(ROOT/'.build/linked-view-runs/20261106T214127Z-linked-view-dfccd81746af/linked_view_document_test.dart.log','diagnostic/before-presence/ios/linked_view_document_test.dart.log')
 copy(ROOT/'.build/linked-view-runs/20261106T214127Z-linked-view-dfccd81746af/linked_view_reopen_test.dart.log','diagnostic/before-presence/ios/linked_view_reopen_test.dart.log')
 for base,domain in [(ROOT/'flutter/assets/wasm','document'),(ROOT/'dataset/flutter/assets/wasm','dataset'),(WORKSPACE/'Muse-Client/packages/muse_appflowy_realtime/assets/wasm','realtime')]:
  for artifact in base.iterdir():
   if artifact.is_file() and artifact.suffix in {'.js','.wasm'}:copy(artifact,'runtime-artifacts/'+domain+'/'+artifact.name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','40-PHASE17-NESTED-SHARED-RULES.zh-CN.md','41-PHASE18-USER-PRESENCE-ROSTER.zh-CN.md','42-PHASE19-DOCUMENT-OUTLINE.zh-CN.md','outline-functional-review/index.html','43-PHASE20-NUMERIC-CELL-INTEGRITY.zh-CN.md','number-functional-review/index.html','siyuan-collaboration-parity.json','44-PHASE21-NUMBER-FORMAT-SETTINGS.zh-CN.md','number-format-functional-review/index.html','45-PHASE22-LINKED-DATABASE-VIEWS.zh-CN.md','linked-view-functional-review/index.html'])
 owned.update((DOCS/'scripts').glob('verify*evidence.py'))
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets','rust/fixtures']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst','.json'})
 for vendor in ['appflowy_view_rules','yrs','outline_reference','number_reference','number_format_reference','appflowy_database','linked_view_reference']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned.update(f for f in (CLOUD/'vendor/yrs').rglob('*') if f.is_file())
 owned.update(CLOUD/name for name in ['Cargo.toml','Cargo.lock'])
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source, fixed upstream references and test inputs; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]},indent=2)+'\n')
 binary=json.loads((ROOT/'.build/p19-cloud-binary.json').read_text());assert sha(CLOUD/'target/debug/appflowy_cloud')==binary['sha256']
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout
 (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 (stage/'result.json').write_text(json.dumps({'phase': 'P22-20261107', 'status': 'partial', 'fullProductAcceptance': 'not-complete', 'parityCases': [], 'android': 'unrun', 'slices': {'datasetRustTests': 62, 'datasetFullTests': 60, 'datasetSdkTests': 3, 'appleUiChecksPerPlatform': 9, 'appleFreshProcessChecksPerPlatform': 3, 'webUiChecks': 10, 'webPeerChecks': 8, 'webReloadChecks': 5, 'nativeWebReadbackAfterCloudRestartChecks': 6}, 'limits': ['Grid linked views do not certify the five full SiYuan layouts, all fields or complete schema concurrency', 'Concurrent field creation with a new view requires a separate qualification gate', 'Original old frontends may still read stale copied row orders; capability negotiation remains open', 'Full SiYuan editing and complete collaboration remain open', 'Android, Windows/Linux and physical IME/keyboard geometry remain unqualified', 'Durable ACK/outbox, production inherited grants, distributed immediate revoke, sharing/comments/history/Agent/Office remain open'], 'fullParityGate': {'status': 'rejected-expected', 'exitCode': 1}},ensure_ascii=False,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P22：共享数据库的独立视图身份\n\nDataset Rust 62、Flutter 60、公共 SDK 3；macOS/iOS 各 9 UI + 3 重开。Web 10、Bob 8、离线 5；Cloud 独占服务重启后 Native 同对象回读 6。\n\n原 CreateLinkedView/Root1/Row4、独立筛选、主成员投影、稳定选择及原 Awareness。Alice 4 视图/2 行、Bob 3 视图/3 行在发布前各自提交，最终 5 视图共享 3 个独立行。原漏行负例与补充位置检查前的旧运行保留在 diagnostic，未算作最终验收。应用 JS 和身份凭据不归档。完整产品 NOT COMPLETE，Android 未运行。\n\n![Desktop](macos/linked-view-concurrent.png)\n![Mobile](ios/linked-view-stale-name.png)\n![Web](linked-view-web-final.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 subprocess.run(['python3',str(DOCS/'scripts/verify_linked_view_evidence.py'),'--root',str(stage),'--source'],check=True)
 stage.rename(dest);print(f'P22 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
