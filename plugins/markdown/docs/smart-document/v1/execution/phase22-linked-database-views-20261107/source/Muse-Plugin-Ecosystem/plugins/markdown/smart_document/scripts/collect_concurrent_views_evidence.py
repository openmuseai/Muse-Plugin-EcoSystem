#!/usr/bin/env python3
"""Freeze P15 stable original rule nodes and bounded original undo qualification."""
import argparse
from datetime import datetime,timezone
import hashlib,importlib.util,json,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['macos','ios']:p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();dest=DOCS/'execution/phase15-concurrent-views-20261107'
 if dest.exists():raise SystemExit('Preserve immutable prior evidence')
 stage=Path(tempfile.mkdtemp(prefix='concurrent-archive-',dir=ROOT/'.build'))
 def copy(src,name):
  assert src.is_file() and not src.is_symlink(),src
  if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt'}:
   text=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',text),src
   assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',text),src
  target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 for platform in ['macos','ios']:
  folder=getattr(a,platform).resolve();assert folder.is_relative_to((ROOT/'.build/concurrent-runs').resolve())
  r=json.loads((folder/'result.json').read_text());assert r['status']=='passed-concurrent-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(7,3)
  for name in ['result.json','concurrent-e2e.json','concurrent-reopen.json','concurrent-editor.png','concurrent-local-branch.png','concurrent-obsolete-undo.png','concurrent_view_document_test.dart.log','concurrent_view_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
 names=['p15-core-final.log','p15-original-yrs-undo-cmake.log','p15-dataset-local-final.log','p15-dataset-analysis-final.log','p15-dataset-sdk-tests.log','p15-dataset-sdk-analysis.log','p15-example-analysis-qualified.log','p15-concurrent-web-analysis-qualified.log','p15-concurrent-web-build-qualified.log','p15-wasm-build.log','p15-yrs-vendor.log','p15-view-rules-vendor.log','p15-native-web-readback.log','p15-realtime-package-analysis.log','p15-realtime-package-tests.log','p15-test-support-analysis.log','p15-browser-build-hashes.json','dataset-wasm-artifacts.json','concurrent-web-public.json','concurrent-web-result.json','concurrent-web-peer.json','concurrent-web-reload.json','concurrent-native-web-readback.json','concurrent-web-alice-split.png','concurrent-web-alice-split.ax.txt','concurrent-web-bob-split.png','concurrent-web-bob-split.ax.txt','concurrent-web-independent-split.ax.txt','concurrent-web-independent-merged.png','concurrent-web-independent-merged.ax.txt','concurrent-web-obsolete-undo.png','concurrent-web-obsolete-undo.ax.txt','concurrent-web-obsolete-toast.png','concurrent-web-obsolete-toast.ax.txt','p15-toast-capture-diagnostic.json','concurrent-web-editor.png','concurrent-web-editor.ax.txt','concurrent-web-peer.ax.txt','concurrent-web-reopen.png','concurrent-web-reopen.ax.txt']
 for name in names:copy(ROOT/'.build'/name,name)
 for name in ['muse_dataset_core.js','muse_dataset_core_bg.wasm']:copy(ROOT/'dataset/flutter/assets/wasm'/name,'runtime-artifacts/'+name)
 for name,label in [('p15-concurrent-view-before.log','original-array-replacement-two-failures.log'),('p15-view-undo-peer-before.log','original-undo-falls-through-one-failure.log'),('p15-original-yrs-undo-tests.log','original-test-dependencies-not-cached.log'),('p15-original-yrs-undo-online.log','original-test-cmake-not-on-path.log'),('concurrent-web-stale-aux-diagnostic.ax.txt','test-aux-missing-model-listener.ax.txt')]:copy(ROOT/'.build'/name,'diagnostic/'+label)
 first=ROOT/'.build/concurrent-runs/20261106T174323Z-concurrent-c3f34a72a2f7'
 copy(first/'concurrent_view_document_test.dart.log','diagnostic/client-frame-observer-used-server-decoder.log')
 spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior);owned=set(prior.owned_files())
 owned.update(DOCS/name for name in ['README.zh-CN.md','35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md','37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md','38-PHASE15-DATABASE-CONCURRENT-RULES.zh-CN.md','scripts/verify_dates_evidence.py','scripts/verify_lifecycle_evidence.py','scripts/verify_view_rules_evidence.py','scripts/verify_concurrent_views_evidence.py'])
 for directory in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets']:
  owned.update(f for f in (ROOT/directory).rglob('*')if f.is_file() and f.suffix in {'.png','.zst'})
 for vendor in ['appflowy_view_rules','yrs']:
  owned.update(f for f in (ROOT/'vendor'/vendor).rglob('*')if f.is_file() and not any(x in {'target','.git'}for x in f.relative_to(ROOT/'vendor'/vendor).parts))
 owned=sorted(owned)
 for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
 (stage/'source-lock.json').write_text(json.dumps({'date':datetime.now(timezone.utc).isoformat(),'mode':'owned source, checksum-pinned optional undo extension and fixture snapshot; not a clean multi-repository release','files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]},indent=2)+'\n')
 binary=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text());assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==binary['sha256'];(stage/'cloud-binary.json').write_text(json.dumps({**binary,'source':'P8 Cloud binary unchanged; P14 exact loopback CORS origin 50946 reused, no new protocol or backend'},indent=2)+'\n')
 gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True);assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout;(stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
 report={'phase':'P15-20261107','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun','slices':{'originalYrsUndoTests':19,'datasetCoreChecks':34,'datasetLocalUniqueChecks':38,'datasetSdkChecks':3,'realtimePackageChecks':2,'appleUiChecksPerPlatform':7,'appleFreshProcessChecksPerPlatform':3,'webUiChecks':10,'webPeerChecks':8,'webReloadChecks':5,'nativeWebReadbackChecks':4},'limits':['current stable node concurrency qualification covers root-level leaf/rule additions and ordering; nested-child intent preservation, same-ID concurrent creation and schema migration remain open','optional bounded undo is selected only by Dataset history; this is not complete document or collaborative history/version restore support','seven basic fields/one Grid, date filtering, original new-row prefill, Chinese collation, grouping/calculation/source blocks and remaining full SiYuan editing remain open','durable ACK, distributed immediate revoke, Host registry/session pooling/inherited grants, UID multi-device roster and scoped wire subscription remain open','physical IME/soft-keyboard geometry, Android, comments/history/Agent/Office and full parity remain open'],'fullParityGate':{'status':'rejected-expected','exitCode':1}}
 (stage/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 (stage/'README.zh-CN.md').write_text('# P15 原稳定规则节点与单项撤销\n\n原整数组替换 2 项失败、原撤销跳过当前命令 1 项失败已保留。使用原 ArrayExt/Map/move_to；Yrs 0.23.5 校验发布包的 64 个原文件，只增加可选单项弹栈 API，原默认 API 与反演/合并/编解码保持原样。原撤销测试 19 项、内容核心 34 项、本地完整组 38 项、公共 SDK 3 项、实时包 2 项通过。\n\nmacOS/iOS 各 7 项 UI、3 项无凭据新进程。网页主端 10 项、同伴 8 项、IndexedDB 重开 5 项、Native 读回 4 项。两端先各自在未发布原字节流的分支提交，再通过原 WS2 合并；HTTP 在合并阶段被阻止。macos 是网页相同对象来源。\n\n应用 JS 仅记录摘要，不复制含合成测试凭据的编译包；实际浏览器 WASM 与运行时摘要逐字节匹配。诊断中的依赖/CMake、客户端帧误用服务端解码及辅助区刷新属于测试准备/呈现问题，不计成功。完整产品仍未验收，Android 未安装。\n\n![两端发布前的本地分支](concurrent-web-alice-split.png)\n![同伴发布前的本地分支](concurrent-web-bob-split.png)\n![iOS 过期命令提示](ios/concurrent-obsolete-undo.png)\n![最终浏览器界面](concurrent-web-editor.png)\n')
 manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]};(stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');stage.rename(dest)
 print(f'P15 archived: {len(manifest["files"])} artifacts including {len(owned)} source/input snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
