#!/usr/bin/env python3
"""Freeze P10 evidence and owned source snapshots; never replace older runs."""
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
    for directory in ['packages/muse_resource_embed','packages/muse_appflowy_transport','packages/muse_appflowy_realtime','packages/muse_content_store','packages/muse_collab_contract','packages/muse_asset_contract','plugins/smart-document','plugins/dataset']:
        base=WORKSPACE/'Muse-Client'/directory
        owned.extend(f for part in ['lib','test','hook'] for f in (base/part).rglob('*.dart'))
        owned.extend(base/name for name in ['pubspec.yaml','pubspec.lock','README.md','README.zh-CN.md'] if (base/name).is_file())
    spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_realtime_evidence.py')
    prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior)
    owned.extend(WORKSPACE/'Muse-Server/AppFlowy-Cloud'/name for name in prior.CLOUD_FILES)
    owned.extend(DOCS/name for name in ['33-PHASE10-EMBEDDED-DATASET.zh-CN.md','scripts/verify_embedded_evidence.py'])
    return sorted(set(owned))
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['macos','ios','bridge-macos']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    dest=DOCS/'execution/phase10-embedded-20261106'
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
        assert report['status']=='passed-embedded-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(6,3)
        for name in ['result.json','embedded-e2e.json','embedded-reopen.json','embedded-editor.png','embedded_document_test.dart.log','embedded_reopen_test.dart.log']:
            copy(folder/name,platform+'/'+name)
    names=['embed-rust-tests.log','embed-dataset-rust-tests.log','embed-document-local-qualified.log',
      'embed-dataset-full-qualified.log','embed-pinned-session-tests.log','embed-resource-tests.log','embed-contract-tests.log',
      'embed-document-cloud-regression.log','embed-doc-analysis-qualified.log','embed-dataset-analysis-qualified.log',
      'embed-dataset-plugin-analysis.log','embed-example-analysis-qualified.log','embed-web-analysis-qualified.log',
      'embed-web-build-qualified.log','embed-web-document-build.log','embed-web-dataset-build.log',
      'wasm-artifacts.json','dataset-wasm-artifacts.json','embed-original-database-source.log',
      'embed-native-web-readback-qualified.log','embedded-web-public.json','embedded-web-result.json',
      'embedded-web-reload.json','embedded-native-web-readback.json','embedded-web-passed.png','embedded-web-reopen.png']
    for name in names:copy(ROOT/'.build'/name,name)
    diagnostics=['embed-first-cell-undo-before.log','embed-doc-tests.log','embed-doc-tests-close-hang.log',
      'embed-native-web-readback.log','embed-native-web-readback-timeout.log','embed-native-readback-sample.txt',
      'embed-resource-test-invalid-helper.log','embed-resource-test-revision-helper.log',
      'embed-document-local-regression.log','embed-dataset-full-regression.log']
    for name in diagnostics:copy(ROOT/'.build'/name,'superseded-or-diagnostic/'+name)
    failed=ROOT/'.build/embedded-runs/20261106T133652Z-embedded-e2a0d5f7bd87'
    for name in ['result.json','embedded_document_test.dart.log']:copy(failed/name,'superseded-or-diagnostic/first-cell-ui/'+name)
    owned=owned_files()
    lock={'date':datetime.now(timezone.utc).isoformat(),'mode':'owned working source snapshot; not a clean multi-repository release',
      'files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)} for f in owned]}
    for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
    (dest/'source-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    previous=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text())
    assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==previous['sha256']
    (dest/'cloud-binary.json').write_text(json.dumps({**previous,'source':'P8 owned Cloud unchanged in P10'},indent=2)+'\n')
    result={'phase':'P10-20261106','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun',
      'slices':{'documentRustTests':20,'datasetRustTests':10,'documentLocalChecks':32,'datasetFullChecks':22,
        'embeddedSessionChecks':4,'resourceSdkChecks':3,'neutralEmbedContractChecks':1,'documentCloudGroups':4,
        'appleUiChecksPerPlatform':6,'appleFreshProcessChecksPerPlatform':3,'webAssertions':9,'webUniqueChecks':7,
        'webReloadChecks':3,'nativeWebReadbackChecks':3},
      'limits':['6 basic field types/one Grid; full 18 fields/5 layouts remain open',
        'production Host catalog/session-owner unification and child resource registry/ACL inheritance remain open',
        'Dataset realtime/presence, full keyboard undo routing and physical mobile IME remain open',
        'same-cell values remain original atomic values; row reference undo is not resource deletion',
        'immediate cross-instance revocation, durable ACK, comments/history/Agent/Office and Android remain open'],
      'fullParityGate':{'status':'rejected-expected','exitCode':1}}
    gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True)
    assert gate.returncode==1 and 'Parity ledger valid' in gate.stdout
    (dest/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
    (dest/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    (dest/'README.zh-CN.md').write_text('''# P10 文档内数据库增量

复用原 AppFlowy 内联块、Database/Row 和共享 Grid，通过中立资源界面贡献连接公共 SDK 子资源会话。
macOS/iOS 各 6 项 UI 与 3 项新进程检查；浏览器 9 次断言（7 个唯一检查）、3 项重载及 Native→Web→Native 3 项。
bridge_macos 是浏览器实际继续编辑的同一组原生来源对象；macos 是随后增加可见正文的产品界面回归，两组对象身份明确分开。

保留首次空单元格撤销丢失后续协作者值的真实失败及修复前 Rust 复现，Host 解析器缓存失败、测试 helper 的摘要/版本错误、冷加载超时与 dyld 采样。
完整 SiYuan/协作门未通过，Android 未安装。source 保存本轮自有源码快照，厂商原版通过 revision、清单与受控补丁引用。

![macOS 正文与数据库](macos/embedded-editor.png)
![iOS 正文与数据库及编辑工具区](ios/embedded-editor.png)
''')
    manifest={'files':[{'path':str(f.relative_to(dest)),'bytes':f.stat().st_size,'sha256':sha(f)} for f in sorted(dest.rglob('*')) if f.is_file()]}
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'P10 archived: {len(manifest["files"])} artifacts including {len(owned)} owned source snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
