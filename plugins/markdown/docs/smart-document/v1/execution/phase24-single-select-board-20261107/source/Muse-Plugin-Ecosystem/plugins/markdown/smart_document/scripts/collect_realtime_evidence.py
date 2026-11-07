#!/usr/bin/env python3
"""Archive P8 original realtime increment without changing the full-parity gate."""
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
CLOUD_FILES = ['libs/appflowy-proto/src/client_message.rs', 'libs/database/src/collab/lifecycle.rs',
 'libs/database/src/collab/mod.rs', 'libs/database/src/collab/collab_storage.rs',
 'services/appflowy-collaborate/src/collab/cache/collab_cache.rs',
 'services/appflowy-collaborate/src/collab/cache/disk_cache.rs',
 'services/appflowy-collaborate/src/collab/collab_store.rs',
 'services/appflowy-collaborate/src/collab/collab_manager.rs',
 'services/appflowy-collaborate/src/group/group_init.rs',
 'services/appflowy-collaborate/src/ws2/actors/session.rs',
 'services/appflowy-collaborate/src/ws2/actors/workspace.rs',
 'src/api/ws.rs', 'src/api/workspace.rs', 'src/application.rs',
 'src/api/file_storage.rs', 'src/api/mod.rs', 'src/api/private_assets.rs']
NEW_CLOUD = ['libs/database/src/collab/lifecycle.rs', 'src/api/private_assets.rs']

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ['macos', 'ios', 'regression']: p.add_argument('--' + arg, type=Path, required=True)
    args = p.parse_args()
    dest = DOCS / 'execution/phase8-realtime-20261106'
    if dest.exists(): raise SystemExit('Never overwrite archived evidence')
    def copy(source, relative):
        assert source.is_file() and not source.is_symlink(), source
        if source.suffix in {'.log', '.txt', '.json', '.md', '.py', '.rs', '.dart'}:
            data = source.read_text()
            assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', data), 'Credential in ' + str(source)
            assert '--DartDefines=' not in data, 'Encoded build definitions in ' + str(source)
        output = dest / relative; output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, output)
    for platform in ['macos', 'ios']:
        folder = getattr(args, platform).resolve()
        assert folder.is_relative_to((ROOT / '.build').resolve())
        report = json.loads((folder / 'result.json').read_text())
        assert report['status'] == 'passed-realtime-slice' and (report['primaryChecks'], report['freshProcessChecks']) == (8, 3)
        for name in ['result.json','realtime-e2e.json','realtime-reopen.json','realtime-editor.png','realtime_document_test.dart.log','realtime_reopen_test.dart.log']:
            copy(folder / name, platform + '/' + name)
    folder = args.regression.resolve()
    assert folder.is_relative_to((ROOT / '.build').resolve())
    report = json.loads((folder / 'summary.json').read_text())
    assert report['status'] == 'passed' and report['native'] is False
    assert len(report['steps']) >= 13 and all(s['exitCode'] == 0 for s in report['steps'])
    for file in folder.iterdir():
        if file.suffix in {'.json','.log'}: copy(file, 'regression/' + file.name)
    names = [
      'ws2-cloud-qualification.json','ws2-cloud-presence.log','ws2-proto-server-tests.log','ws2-ownership-tests.log','ws2-lifecycle-tests.log',
      'realtime-package-tests.log','realtime-package-analysis.log','realtime-rust-tests.log',
      'realtime-wasm-build.log','realtime-wasm-artifacts.json','realtime-web-final-build.log','realtime-web-public.json',
      'realtime-document-adapter-result.json','realtime-permissions-result.json','realtime-cross-block-selection.log',
      'realtime-final-analysis.log','realtime-dev-stack-tests.log',
      'realtime-web-result.json','realtime-web-reload.json','realtime-browser-ui-observations.json',
      'realtime-web-editor.png','realtime-web-collaborators.png','realtime-web-passed.png','realtime-web-reopen.png']
    for name in names: copy(ROOT / '.build' / name, name)
    for name in ['ws2-cloud-before.log', 'ws2-before-authorization.json', 'ws2-cloud-fixed.log']:
        copy(ROOT / '.build' / name, 'superseded/' + name)
    for run in ['20261106T114811Z-realtime-3265ba2ae29f','20261106T114916Z-realtime-ba9565ca783c',
                '20261106T115302Z-realtime-a292b44860e2','20261106T115521Z-realtime-b4bc60ad0df1',
                '20261106T120214Z-realtime-54ccdbbf3770']:
        for name in ['result.json','realtime_document_test.dart.log']:
            copy(ROOT / '.build/realtime-runs' / run / name, 'superseded/' + run + '/' + name)
    patch = subprocess.check_output(['git','-C',str(CLOUD),'diff','--',*[n for n in CLOUD_FILES if n not in NEW_CLOUD]], text=True)
    (dest / 'cloud-owned.patch').write_text(patch)
    for name in NEW_CLOUD: copy(CLOUD / name, 'cloud-new/' + name)
    owned = []
    for directory in ['rust','runtime','dataset','flutter/lib','flutter/hook','flutter/test',
                      'flutter/example/lib','flutter/example/integration_test','flutter/web_example/lib','probes/realtime_client','scripts']:
        for file in (ROOT / directory).rglob('*'):
            rel = file.relative_to(ROOT / directory)
            if any(x in {'target','build','.dart_tool','__pycache__'} for x in rel.parts): continue
            if file.is_file() and (file.suffix in {'.rs','.dart','.py','.md'} or file.name in {'Cargo.toml','Cargo.lock','pubspec.yaml','pubspec.lock'}): owned.append(file)
    for directory in ['flutter','flutter/example','flutter/web_example']:
        owned.extend(ROOT / directory / name for name in ['pubspec.yaml','pubspec.lock'])
    for directory in ['vendor/appflowy_editor','vendor/appflowy_collab','vendor/appflowy_database','vendor/appflowy_proto']:
        owned.extend(ROOT / directory / name for name in ['openmuse-upstream.json','upstream-files.json','openmuse.patch'])
    for directory in ['packages/muse_appflowy_realtime','packages/muse_appflowy_transport','packages/muse_collab_contract',
                      'packages/muse_content_store','packages/muse_asset_contract','plugins/smart-document','plugins/dataset']:
        base = WORKSPACE / 'Muse-Client' / directory
        owned.extend(f for part in ['lib','test','hook'] for f in (base / part).rglob('*.dart'))
        owned.extend(base / name for name in ['pubspec.yaml','pubspec.lock','README.zh-CN.md'] if (base / name).is_file())
    owned.extend(CLOUD / name for name in CLOUD_FILES)
    owned.append(CLOUD / 'src/biz/guest_acl.rs') # existing policy reused, not an owned patch
    owned.extend(DOCS / name for name in ['31-PHASE8-REALTIME-IMPLEMENTATION.zh-CN.md','scripts/verify_realtime_evidence.py'])
    lock = {'date':datetime.now(timezone.utc).isoformat(),'mode':'working-tree increment, not a clean multi-repository release',
            'files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)} for f in sorted(set(owned))]}
    (dest / 'source-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    (dest / 'cloud-binary.json').write_text(json.dumps({'sha256':sha(CLOUD/'target/debug/appflowy_cloud'),
      'features':['use_actix_cors'],'deployment':'isolated loopback fixture only'},indent=2)+'\n')
    result = {'phase':'P8-20261106','status':'partial','fullProductAcceptance':'not-complete','parityCases':[], 'android':'unrun',
      'slices':{'protocolRustTests':4,'neutralDartTests':2,'originalWs2Checks':7,'documentAdapterChecks':6,'guestAclChecks':8,
       'documentFlutterTests':29,'additionalCrossBlockTests':1,'documentRustTests':17,'documentCloudTestGroups':4,
       'appleUiChecksPerPlatform':8,'appleFreshProcessChecksPerPlatform':3,'webChecks':8,'webReloadChecks':3},
      'limits':['WS RID and HTTP acceptance are not durable ACKs','direct browser input automation not qualified; original context-menu paste tested',
        'physical keyboard/IME not certified','distributed immediate permission notifications and client-ID collisions unqualified',
        'same UID multi-device presentation not fully aggregated','Dataset/Office realtime domain adapters and complete SiYuan editor remain open'],
      'fullParityGate':{'status':'rejected-expected','exitCode':1}}
    (dest / 'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    gate = subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True)
    assert gate.returncode == 1 and 'Parity ledger valid' in gate.stdout
    (dest / 'full-parity-gate.log').write_text(gate.stdout + gate.stderr)
    (dest / 'README.zh-CN.md').write_text('''# P8 增量证据

原 AppFlowy WS v2、原 Yrs Awareness、独立传输 package、文档应用绑定、原远端选区绘制、公开 SDK 注入及 Guest 权限。macOS/iOS 各 8 项 UI 和 3 项无凭证新进程检查；实际浏览器 8 项与重载 3 项。详情见 [实施报告](../../31-PHASE8-REALTIME-IMPLEMENTATION.zh-CN.md)。

保留原非成员读写越权、选区偏移缺陷和中间测试/收集失败；不将这些记录标为通过。浏览器输入通过原上下文粘贴，物理键盘/IME 未认证。Android 未安装。完整思源编辑/完整协作门仍拒绝，不能以本增量替代完整交付。
''')
    manifest = {'files':[{'path':str(f.relative_to(dest)),'bytes':f.stat().st_size,'sha256':sha(f)} for f in sorted(dest.rglob('*')) if f.is_file()]}
    (dest / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'P8 archived: {len(manifest["files"])} artifacts, {len(lock["files"])} source fingerprints; full product NOT COMPLETE')
if __name__ == '__main__': main()
