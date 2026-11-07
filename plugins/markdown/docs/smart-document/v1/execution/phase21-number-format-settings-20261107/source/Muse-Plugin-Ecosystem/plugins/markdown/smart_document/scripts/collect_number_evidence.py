#!/usr/bin/env python3
"""Freeze P20 exact numeric values, editor drafts and original row collaboration evidence without secrets."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1';CLOUD=WORKSPACE/'Muse-Server/AppFlowy-Cloud'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase20-numeric-integrity-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='number-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt','.html'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/number-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-number-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(8,3)
  for name in ['result.json','number-e2e.json','number-reopen.json','number-exact-draft.png','number-invalid.png','number-cell-conflict.png','number-field-conflict.png','number-editor.png','number_document_test.dart.log','number_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p20-number-core-third.log', 'p20-number-widget-focus.log', 'p20-dataset-full-first.log', 'p20-dataset-sdk-tests.log', 'p20-dataset-analysis-final.log', 'p20-example-analysis-final.log', 'p20-web-analysis-second.log', 'p20-web-build.log', 'p20-dataset-wasm-build.log', 'p20-native-web-readback.log', 'p20-web-prepare.log', 'p20-cloud-restart.log', 'p20-browser-build-hashes.json', 'p20-frozen-baselines.json', 'p20-frozen-baselines.log', 'p19-cloud-binary.json', 'wasm-artifacts.json', 'dataset-wasm-artifacts.json', 'realtime-wasm-artifacts.json', 'number-web-public.json', 'number-web-prepare.json', 'number-web-result.json', 'number-web-peer.json', 'number-web-reload.json', 'number-native-web-readback.json', 'number-web-exact-draft.ax.txt', 'number-web-exact-draft.png', 'number-web-invalid.ax.txt', 'number-web-invalid.png', 'number-web-cell-conflict.ax.txt', 'number-web-cell-conflict.png', 'number-web-field-conflict.ax.txt', 'number-web-field-conflict.png', 'number-web-final.ax.txt', 'number-web-final.png', 'number-web-peer.ax.txt', 'number-web-peer.png', 'number-web-reload.ax.txt', 'number-web-reload.png']
 for name in names:copy(ROOT/'.build'/name,name)
 copy(ROOT/'.build/p20-number-baseline.log','diagnostic/original-input-boundary-failure.log')
 copy(ROOT/'.build/number-runs/20261106T205234Z-number-ebf79e9dd4eb/number_document_test.dart.log','diagnostic/scientific-draft-deadline.log')
 copy(ROOT/'.build/number-runs/20261106T205532Z-number-c3c413760ed5/number_document_test.dart.log','diagnostic/input-focus-diagnostic.log')
 for base,domain in [(ROOT/'flutter/assets/wasm','document'),(ROOT/'dataset/flutter/assets/wasm','dataset'),(WORKSPACE/'Muse-Client/packages/muse_appflowy_realtime/assets/wasm','realtime')]:
  for artifact in base.iterdir():
   if artifact.is_file() and artifact.suffix in {'.js','.wasm'}:copy(artifact,'runtime-artifacts/'+domain+'/'+artifact.name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','40-PHASE17-NESTED-SHARED-RULES.zh-CN.md','41-PHASE18-USER-PRESENCE-ROSTER.zh-CN.md','42-PHASE19-DOCUMENT-OUTLINE.zh-CN.md','outline-functional-review/index.html','43-PHASE20-NUMERIC-CELL-INTEGRITY.zh-CN.md','number-functional-review/index.html','siyuan-collaboration-parity.json'])
 owned.update((DOCS/'scripts').glob('verify*evidence.py'))
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets','rust/fixtures']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst','.json'})
 for vendor in ['appflowy_view_rules','yrs','outline_reference','number_reference']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned.update(f for f in (CLOUD/'vendor/yrs').rglob('*') if f.is_file())
 owned.update(CLOUD/name for name in ['Cargo.toml','Cargo.lock'])
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source, fixed upstream references and test inputs; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]},indent=2)+'\n')
 binary=json.loads((ROOT/'.build/p19-cloud-binary.json').read_text());assert sha(CLOUD/'target/debug/appflowy_cloud')==binary['sha256']
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout
 (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 (stage/'result.json').write_text(json.dumps({'phase': 'P20-20261107', 'status': 'partial', 'fullProductAcceptance': 'not-complete', 'parityCases': [], 'android': 'unrun', 'slices': {'datasetRustTests': 56, 'datasetFullTests': 54, 'datasetSdkTests': 3, 'appleUiChecksPerPlatform': 8, 'appleFreshProcessChecksPerPlatform': 3, 'webUiChecks': 9, 'webPeerChecks': 5, 'webReloadChecks': 5, 'nativeWebReadbackAfterCloudRestartChecks': 4}, 'limits': ['Original long-currency grouping, full locale/percent/format settings remain open', 'Full SiYuan editing, database fields/views and complete collaboration remain open', 'Draft digest guards are local optimistic checks, not distributed atomic CAS', 'Mixed old-writer/old-parser capability negotiation remains open', 'Android, Windows/Linux and physical IME/keyboard geometry remain unqualified', 'Durable ACK/outbox, distributed immediate revoke, full sharing/comments/history/Agent/Office remain open'], 'fullParityGate': {'status': 'rejected-expected', 'exitCode': 1}},ensure_ascii=False,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P20：数字原值、显示与协作草稿分离\n\nDataset Rust 56、Flutter 54、公共 SDK 3；macOS/iOS 各 8 UI + 3 重开。Web 9、Bob 5、离线 5；Cloud 独占服务重启后 Native 同对象回读 4。\n\n固定原 AppFlowy/SiYuan 参考，保持 Database1/Row4 和原数字字符串；本轮无新协作协议。Cloud 二进制沿用 P19 GC 修复。显示长金额分组仍有差异，未据此宣称数字格式全部对齐。早期失败保存在 diagnostic，不计作通过；应用 JS 与测试身份不复制进证据。完整产品 NOT COMPLETE，Android 未运行。\n\n![Desktop](macos/number-exact-draft.png)\n![Mobile](ios/number-invalid.png)\n![Web](number-web-final.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 subprocess.run(['python3',str(DOCS/'scripts/verify_number_evidence.py'),'--root',str(stage),'--source'],check=True)
 stage.rename(dest);print(f'P20 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
