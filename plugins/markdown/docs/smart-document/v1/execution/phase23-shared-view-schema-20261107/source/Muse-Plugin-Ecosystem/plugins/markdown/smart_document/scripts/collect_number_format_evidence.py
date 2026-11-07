#!/usr/bin/env python3
"""Freeze P21 original field settings and full-capacity money grouping evidence without secrets."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1';CLOUD=WORKSPACE/'Muse-Server/AppFlowy-Cloud'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase21-number-format-settings-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='number-format-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt','.html'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/number-format-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-number-format-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(11,3)
  for name in ['result.json','number-format-e2e.json','number-format-reopen.json','number-format-settings.png','number-format-stale.png','number-format-editor.png','number_format_document_test.dart.log','number_format_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p21-dataset-rust-final.log', 'p21-number-format-widget-first.log', 'p21-dataset-flutter-full.log', 'p21-dataset-sdk-tests.log', 'p21-dataset-analysis.log', 'p21-example-analysis.log', 'p21-web-analysis.log', 'p21-web-build.log', 'p21-dataset-wasm-build.log', 'p21-native-web-readback.log', 'p21-web-prepare.log', 'p21-cloud-restart.log', 'p21-browser-build-hashes.json', 'p21-frozen-baselines.json', 'p21-frozen-baselines.log', 'p21-database-provenance.log', 'p21-format-reference.log', 'p21-number-grouping-after.log', 'p19-cloud-binary.json', 'wasm-artifacts.json', 'dataset-wasm-artifacts.json', 'realtime-wasm-artifacts.json', 'number-format-web-public.json', 'number-format-web-prepare.json', 'number-format-web-result.json', 'number-format-web-peer.json', 'number-format-web-reload.json', 'number-format-native-web-readback.json', 'number-format-web-settings.ax.txt', 'number-format-web-settings.png', 'number-format-web-stale.ax.txt', 'number-format-web-stale.png', 'number-format-web-cell-conflict.ax.txt', 'number-format-web-cell-conflict.png', 'number-format-web-field-conflict.ax.txt', 'number-format-web-field-conflict.png', 'number-format-web-final.ax.txt', 'number-format-web-final.png', 'number-format-web-peer.ax.txt', 'number-format-web-peer.png', 'number-format-web-reload.ax.txt', 'number-format-web-reload.png']
 for name in names:copy(ROOT/'.build'/name,name)
 copy(ROOT/'.build/p21-number-grouping-before.log','diagnostic/original-grouping-failure.log')
 for base,domain in [(ROOT/'flutter/assets/wasm','document'),(ROOT/'dataset/flutter/assets/wasm','dataset'),(WORKSPACE/'Muse-Client/packages/muse_appflowy_realtime/assets/wasm','realtime')]:
  for artifact in base.iterdir():
   if artifact.is_file() and artifact.suffix in {'.js','.wasm'}:copy(artifact,'runtime-artifacts/'+domain+'/'+artifact.name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','40-PHASE17-NESTED-SHARED-RULES.zh-CN.md','41-PHASE18-USER-PRESENCE-ROSTER.zh-CN.md','42-PHASE19-DOCUMENT-OUTLINE.zh-CN.md','outline-functional-review/index.html','43-PHASE20-NUMERIC-CELL-INTEGRITY.zh-CN.md','number-functional-review/index.html','siyuan-collaboration-parity.json','44-PHASE21-NUMBER-FORMAT-SETTINGS.zh-CN.md','number-format-functional-review/index.html'])
 owned.update((DOCS/'scripts').glob('verify*evidence.py'))
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets','rust/fixtures']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst','.json'})
 for vendor in ['appflowy_view_rules','yrs','outline_reference','number_reference','number_format_reference','appflowy_database']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned.update(f for f in (CLOUD/'vendor/yrs').rglob('*') if f.is_file())
 owned.update(CLOUD/name for name in ['Cargo.toml','Cargo.lock'])
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source, fixed upstream references and test inputs; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]},indent=2)+'\n')
 binary=json.loads((ROOT/'.build/p19-cloud-binary.json').read_text());assert sha(CLOUD/'target/debug/appflowy_cloud')==binary['sha256']
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout
 (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 (stage/'result.json').write_text(json.dumps({'phase': 'P21-20261107', 'status': 'partial', 'fullProductAcceptance': 'not-complete', 'parityCases': [], 'android': 'unrun', 'slices': {'datasetRustTests': 58, 'datasetFullTests': 57, 'datasetSdkTests': 3, 'appleUiChecksPerPlatform': 11, 'appleFreshProcessChecksPerPlatform': 3, 'webUiChecks': 12, 'webPeerChecks': 6, 'webReloadChecks': 5, 'nativeWebReadbackAfterCloudRestartChecks': 4}, 'limits': ['Five original format settings do not certify full SiYuan locale/currency/percent semantics', 'Full SiYuan editing, database fields/views and complete collaboration remain open', 'Draft digest guards are local optimistic checks, not distributed atomic CAS', 'Mixed old-writer/old-parser capability negotiation remains open', 'Android, Windows/Linux and physical IME/keyboard geometry remain unqualified', 'Durable ACK/outbox, distributed immediate revoke, full sharing/comments/history/Agent/Office remain open'], 'fullParityGate': {'status': 'rejected-expected', 'exitCode': 1}},ensure_ascii=False,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P21：数字字段设置与完整金额分组\n\nDataset Rust 58、Flutter 57、公共 SDK 3；macOS/iOS 各 11 UI + 3 重开。Web 12、Bob 6、离线 5；Cloud 独占服务重启后 Native 同对象读回 4。\n\n名称/格式在原字段事务中应用；金额继续复用原 Money/LocalFormat/Formatter，只重复原地区分组至 Decimal 容量。原 Database 76 文件 / 7 可逆补丁，资格探针保留 6。原始失败保存在 diagnostic，不计作通过；应用 JS 与测试身份不复制进证据。完整产品 NOT COMPLETE，Android 未运行。\n\n![Desktop](macos/number-format-settings.png)\n![Mobile](ios/number-format-settings.png)\n![Web](number-format-web-final.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 subprocess.run(['python3',str(DOCS/'scripts/verify_number_format_evidence.py'),'--root',str(stage),'--source'],check=True)
 stage.rename(dest);print(f'P21 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
