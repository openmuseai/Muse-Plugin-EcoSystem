#!/usr/bin/env python3
"""Archive the P7 Dataset increment, retaining exact source scope and open gates."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[3]
DOCS = ROOT.parent / 'docs/smart-document/v1'
CLOUD = WORKSPACE / 'Muse-Server/AppFlowy-Cloud'
CLOUD_FILES = ['libs/database/src/collab/lifecycle.rs', 'libs/database/src/collab/mod.rs',
 'libs/database/src/collab/collab_storage.rs', 'services/appflowy-collaborate/src/collab/cache/collab_cache.rs',
 'services/appflowy-collaborate/src/collab/cache/disk_cache.rs', 'services/appflowy-collaborate/src/collab/collab_store.rs',
 'services/appflowy-collaborate/src/group/group_init.rs', 'src/api/workspace.rs',
 'src/api/file_storage.rs', 'src/api/mod.rs', 'src/api/private_assets.rs']
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['macos', 'ios', 'document-regression']: parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    dest = DOCS/'execution/phase7-dataset-20261106'
    if dest.exists(): raise SystemExit('Preserve existing evidence; never overwrite an archive')
    def copy(source, target):
        assert source.is_file() and not source.is_symlink(), source
        output = dest/target; output.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix in {'.log','.txt','.json','.md','.py','.rs','.dart'}:
            text = source.read_text()
            assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', text), 'Credential in '+str(source)
        shutil.copy2(source, output)
    for platform in ['macos','ios']:
        folder = getattr(args,platform).resolve(); assert folder.is_relative_to((ROOT/'.build').resolve())
        receipt = json.loads((folder/'result.json').read_text())
        assert receipt['status']=='passed-dataset-slice' and (receipt['primaryChecks'],receipt['freshProcessChecks'])==(6,4)
        for name in ['result.json','dataset-e2e.json','dataset-reopen.json','dataset-editor.png','dataset_document_test.dart.log','dataset_reopen_test.dart.log']:
            copy(folder/name,platform+'/'+name)
    folder = args.document_regression.resolve(); assert folder.is_relative_to((ROOT/'.build').resolve())
    result = json.loads((folder/'summary.json').read_text())
    assert result['status']=='passed' and (result['browserChecks'],result['reloadChecks'],result['nativeReadbackChecks'])==(10,3,6)
    for file in folder.iterdir():
        if file.suffix in {'.json','.log','.png'} and 'private' not in file.name: copy(file,'document-regression/'+file.name)
    names = ['dataset-core-final.log','dataset-wire-final.log','dataset-runtime-final.log','dataset-local-final-tests.log',
      'dataset-analysis.log','dataset-wasm-build.log','dataset-wasm-artifacts.json',
      'dataset-cloud-final-tests.log','dataset-cloud-result.json','dataset-cloud-deletion-result.json',
      'dataset-document-cloud-final.log','document-cloud-deletion-result.json','dataset-document-full-local.log',
      'dataset-document-lifecycle-analysis.log','dataset-cloud-lifecycle-check.log','dataset-cloud-lifecycle-tests.log',
      'dataset-cloud-lifecycle-build.log','dataset-lifecycle-restart.log',
      'dataset-web-result.json','dataset-web-reload.json','dataset-web-editor.png','dataset-web-reopen.png',
      'dataset-web-analysis.log','dataset-web-build-v2.log','dataset-web-public.json',
      'post-phase6-store-result.json','post-phase6-store-web.png','post-phase6-web-build-v2.log',
      'p7-document-web.png','p7-document-reopen.png']
    for name in names: copy(ROOT/'.build'/name,name)
    for prefix, paths in {
      'transport': ['/tmp/smartdoc-transport-analysis.log','/tmp/smartdoc-transport-tests.log'],
      'content-store': ['/tmp/smartdoc-store-analysis.log','/tmp/smartdoc-store-tests.log'],
      'dataset-plugin': ['/tmp/muse-dataset-plugin-analysis.log','/tmp/muse-dataset-plugin-tests.log'],
    }.items():
        for path in paths: copy(Path(path),'packages/'+prefix+'/'+Path(path).name)
    # Failed intermediate review is retained, never relabeled as accepted.
    for folder,label,files in [
      ('dataset-runs/20261106T050904Z-dataset-1313ce56c91c','accessibility-attached-during-test',['result.json','dataset_reopen_test.dart.log']),
    ]:
        for name in files: copy(ROOT/'.build'/folder/name,'superseded/'+label+'/'+name)
    copy(ROOT/'.build/dataset-cloud-deletion.log','superseded/original-stale-row-deletion-failure.log')
    patch = subprocess.check_output(['git','-C',str(CLOUD),'diff','--',*[f for f in CLOUD_FILES if f not in ['libs/database/src/collab/lifecycle.rs','src/api/private_assets.rs']]],text=True)
    (dest/'cloud-owned.patch').write_text(patch)
    for name in ['libs/database/src/collab/lifecycle.rs','src/api/private_assets.rs']: copy(CLOUD/name,'cloud-new/'+Path(name).name)
    owned = []
    for directory in ['rust','runtime','dataset','flutter/lib','flutter/hook','flutter/test','flutter/example/lib','flutter/example/integration_test','flutter/web_example/lib','scripts']:
        for path in (ROOT/directory).rglob('*'):
            rel=path.relative_to(ROOT/directory)
            if any(p in {'target','build','.dart_tool','__pycache__'} for p in rel.parts): continue
            if path.is_file() and (path.suffix in {'.rs','.dart','.py','.md'} or path.name in {'Cargo.toml','Cargo.lock','pubspec.yaml','pubspec.lock'}): owned.append(path)
    for directory in ['flutter','flutter/example','flutter/web_example']:
        owned.extend(ROOT/directory/name for name in ['pubspec.yaml','pubspec.lock'])
    for directory in ['vendor/appflowy_editor','vendor/appflowy_collab','vendor/appflowy_database']:
        owned.extend(ROOT/directory/name for name in ['openmuse-upstream.json','upstream-files.json','openmuse.patch'])
    for directory in ['packages/muse_asset_contract','packages/muse_collab_contract','packages/muse_appflowy_transport','packages/muse_content_store','plugins/smart-document','plugins/dataset']:
        root=WORKSPACE/'Muse-Client'/directory
        owned.extend(p for part in ['lib','test'] for p in (root/part).rglob('*.dart'))
        owned.extend(root/name for name in ['pubspec.yaml','pubspec.lock','README.zh-CN.md'] if (root/name).is_file())
    owned.extend(CLOUD/name for name in CLOUD_FILES)
    owned.extend(DOCS/name for name in ['30-PHASE7-DATASET-IMPLEMENTATION.zh-CN.md','scripts/verify_dataset_evidence.py'])
    lock={'date':datetime.now(timezone.utc).isoformat(),'mode':'working-tree increment, not a clean multi-repository release',
      'files':[{'path':str(path.relative_to(WORKSPACE)),'sha256':sha(path)} for path in sorted(set(owned))]}
    (dest/'source-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    (dest/'cloud-binary.json').write_text(json.dumps({'sha256':sha(CLOUD/'target/debug/appflowy_cloud'),'features':['use_actix_cors'],'deployment':'isolated loopback fixture only'},indent=2)+'\n')
    result={'phase':'P7-20261106','status':'partial','fullProductAcceptance':'not-complete','parityCases':[], 'android':'unrun',
      'slices':{'datasetRustTests':6,'wireTests':2,'datasetFlutterTests':9,'datasetPluginTests':2,'transportTests':3,'contentStoreTests':1,
       'documentFlutterTests':25,'datasetCloudChecks':6,'rowDeletionHttpChecks':7,'documentDeletionHttpChecks':5,
       'appleDatasetUiChecksPerPlatform':6,'appleDatasetFreshProcessChecksPerPlatform':4,'datasetWebChecks':8,'datasetWebReloadChecks':3,
       'documentWebChecks':10,'documentWebReloadChecks':3,'documentNativeReadbackChecks':6},
      'remaining':['complete SiYuan 18 fields/5 views and editing corpus','authorized child-session document embedding','same-text-cell character collaboration','WS presence and dynamic ACL/revocation/share/comments/history','durable ACK and all-ingress domain validation','Agent/Office and production Host release'],
      'limits':['same-cell values currently use original row cell LWW; independent cells merge','lifecycle guards preserve original unregistered-ID creation path; not a durable object registry','WS v2 and queue/delete race linearization remain open','Android not installed under persistent user instruction'],
      'fullParityGate':{'status':'rejected-expected','exitCode':1}}
    (dest/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True)
    assert gate.returncode==1 and 'Parity ledger valid' in gate.stdout,gate.stdout+gate.stderr
    (dest/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
    (dest/'README.zh-CN.md').write_text('''# P7 增量证据\n\n原 Database/Row 基础 Grid、公开 SDK 资源、独立内容/持久化/传输，以及注册对象删除保护。macOS/iOS 各 6 项 UI/协作检查和 4 项无凭证新进程检查，Web 8 项与重载 3 项。旧智能文档完整浏览器回归 10/3/6 继续通过。\n\n保留原删除失败及测试期间附加原生无障碍检查触发的清理断言；当前通过结果见 macos/ios 回执。没有跳过失败检查或关闭测试框架断言。Android 未运行，生产 Host 未发布，完整功能与协作门仍未完成。\n''')
    manifest={'files':[{'path':str(p.relative_to(dest)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(dest.rglob('*')) if p.is_file()]}
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'P7 archived: {len(manifest["files"])} artifacts, {len(lock["files"])} source fingerprints; full product NOT COMPLETE')
if __name__=='__main__': main()
