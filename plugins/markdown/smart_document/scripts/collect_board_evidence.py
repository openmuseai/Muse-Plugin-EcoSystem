#!/usr/bin/env python3
"""Freeze P24 original single-select board, shared rows and UI evidence without secrets."""
import argparse,hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1';CLOUD=WORKSPACE/'Muse-Server/AppFlowy-Cloud'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase24-single-select-board-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='board-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt','.html'}:
   value=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',value),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/board-runs').resolve())
  report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-board-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(9,3)
  for name in ['result.json','board-e2e.json','board-reopen.json','board-stale.png','board-cards.png','board-editor.png','board_document_test.dart.log','board_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p24-dataset-core.log','p24-dataset-flutter.log','p24-dataset-sdk-tests.log','p24-dataset-analysis.log','p24-example-analysis.log','p24-web-analysis.log','p24-web-build.log','p24-dataset-wasm-build.log','p24-native-web-readback.log','p24-web-prepare.log','p24-cloud-restart.log','p24-browser-build-hashes.json','p24-browser-build-check.log','p24-frozen-baselines.json','p24-frozen-baselines.log','p24-board-reference.log','p19-cloud-binary.json','wasm-artifacts.json','dataset-wasm-artifacts.json','realtime-wasm-artifacts.json','board-web-public.json','board-web-prepare.json','board-web-result.json','board-web-peer.json','board-web-reload.json','p24-native-web-readback.json']
 names += ['board-web-'+state+suffix for state in ['alice-branch','bob-branch','base','record','moved','stale','undo','final','peer','reload'] for suffix in ['.ax.txt','.png']]
 for name in names:copy(ROOT/'.build'/name,name)
 for name in ['result.json','board-e2e.json','board_document_test.dart.log','board_reopen_test.dart.log']:
  copy(ROOT/'.build/board-runs/20261106T230016Z-board-69db15cb6812'/name,'diagnostic/inter-build-projection-change/'+name)
 copy(ROOT/'.build/p24-web-before-number-field/board_main.dart','diagnostic/web-fixture-before-number-field.dart')
 for base,domain in [(ROOT/'flutter/assets/wasm','document'),(ROOT/'dataset/flutter/assets/wasm','dataset'),(WORKSPACE/'Muse-Client/packages/muse_appflowy_realtime/assets/wasm','realtime')]:
  for artifact in base.iterdir():
   if artifact.is_file() and artifact.suffix in {'.js','.wasm'}:copy(artifact,'runtime-artifacts/'+domain+'/'+artifact.name)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','39-PHASE16-DATABASE-DATE-FILTER-PREFILL.zh-CN.md','40-PHASE17-NESTED-SHARED-RULES.zh-CN.md','41-PHASE18-USER-PRESENCE-ROSTER.zh-CN.md','42-PHASE19-DOCUMENT-OUTLINE.zh-CN.md','outline-functional-review/index.html','43-PHASE20-NUMERIC-CELL-INTEGRITY.zh-CN.md','number-functional-review/index.html','siyuan-collaboration-parity.json','44-PHASE21-NUMBER-FORMAT-SETTINGS.zh-CN.md','number-format-functional-review/index.html','45-PHASE22-LINKED-DATABASE-VIEWS.zh-CN.md','linked-view-functional-review/index.html','46-PHASE23-SHARED-VIEW-SCHEMA.zh-CN.md','schema-view-functional-review/index.html','47-PHASE24-SINGLE-SELECT-BOARD.zh-CN.md','board-functional-review/index.html'])
 owned.update((DOCS/'scripts').glob('verify*evidence.py'))
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets','rust/fixtures']:
  owned.update(f for f in (ROOT/directory).rglob('*') if f.is_file() and f.suffix in {'.png','.zst','.json'})
 for vendor in ['appflowy_view_rules','yrs','outline_reference','number_reference','number_format_reference','appflowy_database','linked_view_reference','schema_view_reference','board_reference']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*') if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned.update(f for f in (CLOUD/'vendor/yrs').rglob('*') if f.is_file())
 owned.update(CLOUD/name for name in ['Cargo.toml','Cargo.lock'])
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source, fixed upstream references and test inputs; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]},indent=2)+'\n')
 binary=json.loads((ROOT/'.build/p19-cloud-binary.json').read_text());assert sha(CLOUD/'target/debug/appflowy_cloud')==binary['sha256']
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid' in gate.stdout
 (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 (stage/'result.json').write_text(json.dumps({'phase':'P24-20261107','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun','slices':{'datasetRustTests':66,'datasetFullTests':64,'datasetSdkTests':3,'appleUiChecksPerPlatform':9,'appleFreshProcessChecksPerPlatform':3,'webUiChecks':11,'webPeerChecks':10,'webReloadChecks':6,'nativeWebReadbackAfterCloudRestartChecks':7},'limits':['Single-select grouped board only; other grouping types and full five layouts remain open','Card manual ordering, cover settings, group editing and grouping-field changes remain open','Concurrent moves of the same register retain original Yrs semantics, not global CAS','Full SiYuan editing, production Host permissions, durable ACK/outbox, sharing/comments/history/Agent/Office remain open','Android, Windows/Linux and physical IME/keyboard geometry remain unqualified'],'fullParityGate':{'status':'rejected-expected','exitCode':1}},ensure_ascii=False,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P24：原记录的单选分组看板\n\nDataset Rust 66、Flutter 64、公共 SDK 3；macOS/iOS 各 9 UI + 3 重开。Web 11、Bob 10、离线 6；Cloud 重启后 Native 同对象回读 7。\n\n原 GroupSetting 与 Option ID 派生列，卡片引用原行；移动与详情共用原 Row4。真正独立分支合并，过期移动拒绝，原撤销/重做保留远端分组与数字。早期构建间投影变化的重开失败保存在 diagnostic，不计作通过。应用 JS 和凭据不归档。完整产品 NOT COMPLETE，Android 未运行。\n\n![Desktop](macos/board-cards.png)\n![Mobile](ios/board-cards.png)\n![Web](board-web-final.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 subprocess.run(['python3',str(DOCS/'scripts/verify_board_evidence.py'),'--root',str(stage),'--source'],check=True)
 stage.rename(dest);print(f'P24 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
