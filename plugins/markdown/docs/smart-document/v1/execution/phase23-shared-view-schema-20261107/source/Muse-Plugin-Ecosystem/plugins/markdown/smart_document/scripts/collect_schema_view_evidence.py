#!/usr/bin/env python3
"""Freeze P23 shared original field schema across concurrent views evidence without secrets."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1';CLOUD=WORKSPACE/'Muse-Server/AppFlowy-Cloud'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase23-shared-view-schema-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='schema-view-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt','.html'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/schema-view-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-schema-view-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(11,3)
  for name in ['result.json','schema-view-e2e.json','schema-view-reopen.json','schema-view-concurrent.png','schema-view-field.png','schema-view-stale-name.png','schema-view-missing.png','schema-view-editor.png','schema_view_document_test.dart.log','schema_view_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p23-fields-core-final.log', 'p23-dataset-full.log', 'p23-dataset-sdk-tests.log', 'p23-dataset-analysis.log', 'p23-example-analysis.log', 'p23-web-analysis-first.log', 'p23-web-build.log', 'p23-dataset-wasm-build.log', 'p23-native-web-readback.log', 'p23-web-prepare.log', 'p23-cloud-restart.log', 'p23-browser-build-hashes.json', 'p23-frozen-baselines.json', 'p23-frozen-baselines.log', 'p23-schema-reference-qualified.log', 'p19-cloud-binary.json', 'wasm-artifacts.json', 'dataset-wasm-artifacts.json', 'realtime-wasm-artifacts.json', 'schema-view-web-public.json', 'schema-view-web-prepare.json', 'schema-view-web-result.json', 'schema-view-web-peer.json', 'schema-view-web-reload.json', 'schema-view-native-web-readback.json', 'schema-view-web-alice-branch.ax.txt', 'schema-view-web-alice-branch.png', 'schema-view-web-bob-branch.ax.txt', 'schema-view-web-bob-branch.png', 'schema-view-web-base.ax.txt', 'schema-view-web-base.png', 'schema-view-web-filter.ax.txt', 'schema-view-web-filter.png', 'schema-view-web-field-edit.ax.txt', 'schema-view-web-field-edit.png', 'schema-view-web-stale.ax.txt', 'schema-view-web-stale.png', 'schema-view-web-missing.ax.txt', 'schema-view-web-missing.png', 'schema-view-web-presence-before.ax.txt', 'schema-view-web-presence-before.png', 'schema-view-web-presence-cleared.ax.txt', 'schema-view-web-presence-cleared.png', 'schema-view-web-final.ax.txt', 'schema-view-web-final.png', 'schema-view-web-peer.ax.txt', 'schema-view-web-peer.png', 'schema-view-web-reload.ax.txt', 'schema-view-web-reload.png']
 for name in names:copy(ROOT/'.build'/name,name)
 copy(ROOT/'.build/p23-field-order-before.log','diagnostic/original-field-order-failure.log')
 copy(ROOT/'.build/p23-ios-before-row-scroll.png','diagnostic/ios-before-row-scroll.png')
 copy(ROOT/'.build/schema-view-runs/20261106T221641Z-schema-view-a0e082b78573/result.json','diagnostic/unbuilt-second-row/result.json')
 copy(ROOT/'.build/schema-view-runs/20261106T221641Z-schema-view-a0e082b78573/schema_view_document_test.dart.log','diagnostic/unbuilt-second-row/schema_view_document_test.dart.log')
 copy(ROOT/'.build/schema-view-runs/20261106T221936Z-schema-view-8fd4c789c2b8/result.json','diagnostic/offscreen-full-list-center/result.json')
 copy(ROOT/'.build/schema-view-runs/20261106T221936Z-schema-view-8fd4c789c2b8/schema_view_document_test.dart.log','diagnostic/offscreen-full-list-center/schema_view_document_test.dart.log')
 for base,domain in [(ROOT/'flutter/assets/wasm','document'),(ROOT/'dataset/flutter/assets/wasm','dataset'),(WORKSPACE/'Muse-Client/packages/muse_appflowy_realtime/assets/wasm','realtime')]:
  for artifact in base.iterdir():
   if artifact.is_file() and artifact.suffix in {'.js','.wasm'}:copy(artifact,'runtime-artifacts/'+domain+'/'+artifact.name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','40-PHASE17-NESTED-SHARED-RULES.zh-CN.md','41-PHASE18-USER-PRESENCE-ROSTER.zh-CN.md','42-PHASE19-DOCUMENT-OUTLINE.zh-CN.md','outline-functional-review/index.html','43-PHASE20-NUMERIC-CELL-INTEGRITY.zh-CN.md','number-functional-review/index.html','siyuan-collaboration-parity.json','44-PHASE21-NUMBER-FORMAT-SETTINGS.zh-CN.md','number-format-functional-review/index.html','45-PHASE22-LINKED-DATABASE-VIEWS.zh-CN.md','linked-view-functional-review/index.html','46-PHASE23-SHARED-VIEW-SCHEMA.zh-CN.md','schema-view-functional-review/index.html'])
 owned.update((DOCS/'scripts').glob('verify*evidence.py'))
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets','rust/fixtures']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst','.json'})
 for vendor in ['appflowy_view_rules','yrs','outline_reference','number_reference','number_format_reference','appflowy_database','linked_view_reference','schema_view_reference']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned.update(f for f in (CLOUD/'vendor/yrs').rglob('*') if f.is_file())
 owned.update(CLOUD/name for name in ['Cargo.toml','Cargo.lock'])
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source, fixed upstream references and test inputs; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]},indent=2)+'\n')
 binary=json.loads((ROOT/'.build/p19-cloud-binary.json').read_text());assert sha(CLOUD/'target/debug/appflowy_cloud')==binary['sha256']
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout
 (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 (stage/'result.json').write_text(json.dumps({'phase': 'P23-20261107', 'status': 'partial', 'fullProductAcceptance': 'not-complete', 'parityCases': [], 'android': 'unrun', 'slices': {'datasetRustTests': 63, 'datasetFullTests': 60, 'datasetSdkTests': 3, 'appleUiChecksPerPlatform': 11, 'appleFreshProcessChecksPerPlatform': 3, 'webUiChecks': 13, 'webPeerChecks': 9, 'webReloadChecks': 5, 'nativeWebReadbackAfterCloudRestartChecks': 7}, 'limits': ['Global schema projection does not certify full field deletion/conversion/visibility or five complete layouts', 'Original old frontends may still read stale copied field orders; capability negotiation remains open', 'Text cells remain original register values, not character-level collaboration', 'Full SiYuan editing, production permissions, durable ACK/outbox, sharing/comments/history/Agent/Office remain open', 'Android, Windows/Linux and physical IME/keyboard geometry remain unqualified'], 'fullParityGate': {'status': 'rejected-expected', 'exitCode': 1}},ensure_ascii=False,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P23：多视图共享字段与原记录编辑\n\nDataset Rust 63、Flutter 60、公共 SDK 3；macOS/iOS 各 11 UI + 3 重开。Web 13、Bob 9、离线 5；Cloud 重启后 Native 同对象回读 7。\n\n原 FieldMap 为 schema 真源，视图顺序只派生显示；Grid、记录详情和规则预检共用同一字段集合。新视图/字段/记录分支独立提交后合并，五个视图共享五个原字段、三条独立记录；原生与 Web 行值同时保留。原漏列负例和两次 iOS 定位失败保存在 diagnostic，不计作通过。最终使用可见区域内真实滑动并严格命中单元格。应用 JS 和身份凭据不归档。完整产品 NOT COMPLETE，Android 未运行。\n\n![Desktop](macos/schema-view-field.png)\n![Mobile](ios/schema-view-field.png)\n![Web](schema-view-web-final.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 subprocess.run(['python3',str(DOCS/'scripts/verify_schema_view_evidence.py'),'--root',str(stage),'--source'],check=True)
 stage.rename(dest);print(f'P23 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
