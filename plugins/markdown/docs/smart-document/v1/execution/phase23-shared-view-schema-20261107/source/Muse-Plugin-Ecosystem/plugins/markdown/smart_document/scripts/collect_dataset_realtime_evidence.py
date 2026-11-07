#!/usr/bin/env python3
"""Freeze P11 evidence and owned source snapshots; never replace older runs."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
WORKSPACE=ROOT.parents[3]
DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def owned_files():
    owned=[ROOT/'README.zh-CN.md']
    for directory in ['rust','runtime','dataset','flutter/lib','flutter/hook','flutter/test','flutter/example/lib','flutter/example/test','flutter/example/integration_test','flutter/web_example/lib','scripts']:
        for f in (ROOT/directory).rglob('*'):
            rel=f.relative_to(ROOT/directory)
            if any(x in {'target','build','.dart_tool','__pycache__'} for x in rel.parts):continue
            if f.is_file() and (f.suffix in {'.rs','.dart','.py','.md'} or f.name in {'Cargo.toml','Cargo.lock','pubspec.yaml','pubspec.lock'}):owned.append(f)
    for directory in ['flutter','flutter/example','flutter/web_example']:
        owned.extend(ROOT/directory/name for name in ['pubspec.yaml','pubspec.lock'])
    for directory in ['vendor/appflowy_editor','vendor/appflowy_collab','vendor/appflowy_database','vendor/appflowy_proto']:
        owned.extend(ROOT/directory/name for name in ['openmuse-upstream.json','upstream-files.json','openmuse.patch'])
    for directory in ['packages/muse_resource_embed','packages/muse_collab_widgets','packages/muse_appflowy_transport','packages/muse_appflowy_realtime','packages/muse_content_store','packages/muse_collab_contract','packages/muse_asset_contract','plugins/smart-document','plugins/dataset']:
        base=WORKSPACE/'Muse-Client'/directory
        owned.extend(f for part in ['lib','test','hook'] for f in (base/part).rglob('*.dart'))
        owned.extend(base/name for name in ['pubspec.yaml','pubspec.lock','README.md','README.zh-CN.md'] if (base/name).is_file())
    spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_realtime_evidence.py')
    prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior)
    owned.extend(WORKSPACE/'Muse-Server/AppFlowy-Cloud'/name for name in prior.CLOUD_FILES)
    owned.extend(DOCS/name for name in ['34-PHASE11-DATASET-REALTIME.zh-CN.md','scripts/verify_dataset_realtime_evidence.py'])
    return sorted(set(owned))
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['macos','ios','bridge-macos']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    dest=DOCS/'execution/phase11-dataset-realtime-20261106'
    if dest.exists():raise SystemExit('Preserve existing immutable archive')
    def copy(src,name):
        assert src.is_file() and not src.is_symlink(),src
        if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt'}:
            content=src.read_text()
            assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',content),src
            assert not re.search(r'--DartDefines=[A-Za-z0-9+/]{32,}',content),src
        target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
    for platform in ['macos','ios','bridge_macos']:
        folder=getattr(args,platform).resolve()
        assert folder.is_relative_to((ROOT/'.build').resolve())
        report=json.loads((folder/'result.json').read_text())
        assert report['status']=='passed-dataset_realtime-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(8,3)
        for name in ['result.json','dataset_realtime-e2e.json','dataset_realtime-reopen.json','dataset_realtime-editor.png','dataset_realtime-members.png','dataset_realtime_document_test.dart.log','dataset_realtime_reopen_test.dart.log']:
            copy(folder/name,platform+'/'+name)
    names=['dataset-realtime-rust-projection.log','dataset-realtime-document-regression.log','dataset-realtime-full-regression.log',
      'dataset-realtime-cloud-result.json','dataset-realtime-permissions-result.json','dataset-realtime-permissions-qualified.log',
      'dataset-realtime-sdk-tests.log','dataset-realtime-sdk-analysis.log','dataset-realtime-shared-widgets-tests.log',
      'dataset-realtime-document-analysis.log','dataset-realtime-analysis-qualified.log','dataset-realtime-document-plugin-analysis.log',
      'dataset-realtime-web-analysis-final.log','dataset-realtime-web-build-final.log','dataset-realtime-example-analysis-qualified.log',
      'dataset-realtime-original-document-cloud.log','dataset-realtime-wasm-build.log','dataset-wasm-artifacts.json',
      'dataset-realtime-web-public.json','dataset-realtime-web-result.json','dataset-realtime-web-peer.json','dataset-realtime-web-reload.json',
      'dataset-realtime-native-web-readback.json','dataset-realtime-native-web-readback.log',
      'dataset-realtime-web-alice.png','dataset-realtime-web-bob.png','dataset-realtime-web-reopen.png',
      'dataset-realtime-web-conflict.png','dataset-realtime-web-conflict.ax.txt',
      'dataset-realtime-web-alice.ax.txt','dataset-realtime-web-bob.ax.txt','dataset-realtime-web-status.png','dataset-realtime-web-status.ax.txt']
    for name in names:copy(ROOT/'.build'/name,name)
    copy(ROOT/'.build/dataset-realtime-permissions-first.log','superseded-or-diagnostic/delete-without-required-json.log')
    for folder,label in [('20261106T142449Z-dataset_realtime-76441e7606ea','missing-upstream-extension-import'),('20261106T142622Z-dataset_realtime-63a8f873d450','concurrent-generated-swift-package')]:
        failed=ROOT/'.build/dataset_realtime-runs'/folder
        for name in ['result.json','dataset_realtime_document_test.dart.log']:copy(failed/name,'superseded-or-diagnostic/'+label+'/'+name)
    owned=owned_files()
    lock={'date':datetime.now(timezone.utc).isoformat(),'mode':'owned working source snapshot; not a clean multi-repository release',
      'files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)} for f in owned]}
    for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
    (dest/'source-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    previous=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text())
    assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==previous['sha256']
    (dest/'cloud-binary.json').write_text(json.dumps({**previous,'source':'P8 owned Cloud unchanged in P11'},indent=2)+'\n')
    result={'phase':'P11-20261106','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun',
      'slices':{'documentRustTests':20,'datasetRustTests':10,'documentLocalChecks':32,'datasetFullChecks':29,
        'resourceSdkChecks':3,'sharedPresenceUiChecks':1,'documentCloudGroups':4,'liveWireChecks':6,'actualGuestChecks':7,
        'appleUiChecksPerPlatform':8,'appleFreshProcessChecksPerPlatform':3,'webAliceChecks':9,'webBobChecks':7,
        'webReloadChecks':5,'nativeWebReadbackChecks':4},
      'limits':['6 basic field types/one Grid; complete SiYuan editing/database range remains open',
        'original workspace broadcast; 128-row client attention window is not scoped wire subscription or qualified 1000-row interactive capacity',
        'resource registry, inherited grants and cross-instance immediate revocation remain open; explicit root/row Guest grants were qualified',
        'UID multi-device roster aggregation/client-id registry, contextual keyboard history and physical IME remain open',
        'durable ACK/offline commands, comments/history/Agent/Office and Android remain open'],
      'fullParityGate':{'status':'rejected-expected','exitCode':1}}
    gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True)
    assert gate.returncode==1 and 'Parity ledger valid' in gate.stdout
    (dest/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
    (dest/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    (dest/'README.zh-CN.md').write_text('# P11 独立数据库实时协作\n\n复用原 WS2、Yrs Awareness、Database 1/Row 4、共享 Grid 和公共资源会话。Native 6 项真实通路检查、实际 Guest 7 项；macOS/iOS 各 8 项 UI、3 项新进程恢复。\n双浏览器 Alice 9 项、Bob 7 项、重载 5 项；Native→Web→Native 4 项。同格草稿冲突保留真实 AX 文本和截图，实际 core undo/redo 被观测而未替换。\n\nbridge_macos 是浏览器继续编辑的原生来源，macos/ios 是最终状态文字与同一功能的回归。source 保存自有代码快照，原版依赖仍由固定 revision/清单/补丁确定。\n原 WS2 为工作区广播，当前客户端关注前 128 行，未把它称为协议级订阅。完整 SiYuan/协作门保持拒绝，Android 未安装。\n\n![数据库单元格在线状态](macos/dataset_realtime-editor.png)\n![iOS 在线成员与表格](ios/dataset_realtime-editor.png)\n![真实浏览器草稿冲突](dataset-realtime-web-conflict.png)\n')
    manifest={'files':[{'path':str(f.relative_to(dest)),'bytes':f.stat().st_size,'sha256':sha(f)} for f in sorted(dest.rglob('*')) if f.is_file()]}
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'P11 archived: {len(manifest["files"])} artifacts including {len(owned)} owned source snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
