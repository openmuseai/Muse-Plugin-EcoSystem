#!/usr/bin/env python3
"""Freeze P14 original rule reuse and actual shared view UI qualification."""
import argparse
from datetime import datetime,timezone
import hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase14-view-rules-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='view-rules-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt'}:
   text=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',text),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',text),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/rules-runs').resolve())
  r=json.loads((folder/'result.json').read_text());assert r['status']=='passed-rules-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(7,3)
  for name in ['result.json','rules-e2e.json','rules-reopen.json','rules-editor.png','rules-filter-dialog.png','rules-sort-dialog.png','rules-peer-conflict.png','view_rules_document_test.dart.log','view_rules_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 for name in ['p14-core-qualified.log','p14-original-view-rules-tests-offline.log','p14-dataset-local-qualified.log','p14-dataset-analysis-qualified.log','p14-dataset-sdk-tests.log','p14-dataset-sdk-analysis.log','p14-example-analysis-qualified.log','p14-view-rules-web-analysis-qualified.log','p14-view-rules-web-build-qualified.log','p14-wasm-build-qualified.log','p14-view-rules-vendor.log','p14-native-web-readback-qualified.log','dataset-wasm-artifacts.json','rules-web-public.json','rules-web-result.json','rules-web-peer.json','rules-web-reload.json','rules-native-web-readback.json','rules-web-hidden.png','rules-web-hidden.ax.txt','rules-web-conflict.png','rules-web-conflict.ax.txt','rules-web-editor.png','rules-web-editor.ax.txt','rules-web-peer.ax.txt','rules-web-reopen.png','rules-web-reopen.ax.txt']:copy(ROOT/'.build'/name,name)
 for name in ['muse_dataset_core.js','muse_dataset_core_bg.wasm']:copy(ROOT/'dataset/flutter/assets/wasm'/name,'runtime-artifacts/'+name)
 for name,label in [('p14-core-view-rules.log','test-setup-missing-amount-field.log'),('p14-view-rules-surface-first.log','test-setup-missing-title.log'),('p14-dataset-local-full.log','incorrect-test-filename-selection.log'),('rules-web-action-target-diagnostic.ax.txt','browser-missed-http-toggle.ax.txt')]:copy(ROOT/'.build'/name,'diagnostic/'+label)
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior)
 owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','scripts/verify_dates_evidence.py','scripts/verify_lifecycle_evidence.py','scripts/verify_view_rules_evidence.py'])
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets']:
  owned.update(f for f in (ROOT/directory).rglob('*')if f.is_file() and f.suffix in {'.png','.zst'})
 owned.update(f for f in (ROOT/'vendor/appflowy_view_rules').rglob('*')if f.is_file() and not any(x in {'target','.git'} for x in f.relative_to(ROOT/'vendor/appflowy_view_rules').parts))
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source, fixed rule extraction and fixture snapshot; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]},indent=2)+'\n')
 binary=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text());assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==binary['sha256']
 (stage/'cloud-binary.json').write_text(json.dumps({**binary,'source':'P8 Cloud binary unchanged; exact loopback CORS origin 50946 added for P14 fixture'},indent=2)+'\n')
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout
 (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 report={'phase':'P14-20261107','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun','slices':{'originalFilterTests':14,'datasetCoreChecks':25,'datasetLocalUniqueChecks':36,'datasetSdkChecks':3,'appleUiChecksPerPlatform':7,'appleFreshProcessChecksPerPlatform':3,'webUiChecks':9,'webPeerChecks':4,'webReloadChecks':4,'nativeWebReadbackChecks':4},'limits':['seven basic fields/one Grid; filters on text/URL/number/checkbox/single/multi select; date filtering and original new-row prefill remain open','core covers multiple sort keys; actual UI/browser primarily qualifies one primary key, not full multi-key priority interaction','full SiYuan fields/views, Chinese text collation, grouping/calculation/source block and remaining editor parity remain open','durable ACK, distributed immediate revoke, Host registry/session pooling/inherited grants, UID multi-device roster and scoped wire subscription remain open','simultaneous view array configuration conflicts and global CAS/atomic semantics remain open; local draft hashes are not server CAS','physical IME/soft-keyboard geometry, Android, comments/history/Agent/Office and full parity remain open'],'fullParityGate':{'status':'rejected-expected','exitCode':1}}
 (stage/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P14 原数据库共享视图规则\n\n复用固定 AppFlowy 客户端纯筛选器和原测试，使用原 Root1/Row4/WS2。原规则 14 项、内容核心 25 项、数据库本地完整组 36 项、公共 SDK 3 项；macOS/iOS 各 7 项实际 UI 与 3 项新进程恢复。网页 9 项、协作者 4 项、IndexedDB 重开 4 项、Native 读回 4 项。\n\nmacos 是网页继续编辑的同一原生对象来源。筛选显示与协作依赖分离；真正挡住 HTTP 后，隐藏行仍通过原 WS2 更新并重新显示。保留原错误配置、字段/单元格编码，旧草稿不得覆盖同伴新配置。浏览器主要验收单主排序键，多键优先级由核心测试覆盖。\n\n诊断中的缺字段/缺标题和错误测试文件名属于测试准备错误，不计成功。完整产品仍未验收，Android 未安装。\n\n![iOS 筛选弹层](ios/rules-filter-dialog.png)\n![实际浏览器编辑区](rules-web-editor.png)\n![实际浏览器旧草稿冲突](rules-web-conflict.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');stage.rename(dest)
 print(f'P14 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
