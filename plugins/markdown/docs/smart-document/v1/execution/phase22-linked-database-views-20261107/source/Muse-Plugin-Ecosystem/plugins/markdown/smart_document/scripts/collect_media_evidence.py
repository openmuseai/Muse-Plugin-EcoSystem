#!/usr/bin/env python3
"""Archive a reviewable P6 increment without credentials or full-product claims."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
WORKSPACE=ROOT.parents[3]
DOCS=ROOT.parent/'docs/smart-document/v1'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['macos','ios','web']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    destination=DOCS/'execution/phase6-media-20261106'
    if destination.exists():raise SystemExit('Evidence already exists; preserve the archive and choose an explicitly reviewed new increment')
    def copy(source,target):
        if not source.is_file() or source.is_symlink():raise ValueError('Missing/unsafe artifact: '+str(source))
        output=destination/target;output.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,output)
    for platform in ['macos','ios']:
        source=getattr(args,platform).resolve()
        assert source.is_relative_to((ROOT/'.build').resolve())
        result=json.loads((source/'result.json').read_text())
        assert result['status']=='passed-media-slice' and result['primaryChecks']==7 and result['freshProcessChecks']==4
        for name in ['result.json','media-e2e.json','media-reopen.json','media-editor.png','media_document_test.dart.log','media_reopen_test.dart.log']:copy(source/name,platform+'/'+name)
    web=args.web.resolve();assert web.is_relative_to((ROOT/'.build').resolve())
    report=json.loads((web/'summary.json').read_text())
    assert report['status']=='passed' and (report['browserChecks'],report['reloadChecks'],report['nativeReadbackChecks'])==(10,3,6)
    for path in web.iterdir():
        if path.suffix in ['.json','.log','.png'] and 'private' not in path.name:copy(path,'web-regression/'+path.name)
    extras=['phase6-rust.log','phase6-analysis.log','phase6-local.log','phase6-media-final.log','phase6-wasm-build.log','phase6-private-assets-result.json',
            'phase6-cloud-check.log','phase6-cloud-tests.log','phase6-cloud-build.log','phase6-web-editor.png','phase6-web-reopen.png',
            'phase6-web-filepicker.png','phase6-web-filepicker-ax.txt','phase6-web-filepicker-readback.log','phase6-web-filepicker-readback.json',
            'database-native-probe.log','database-wasm-probe.log','database-native-patched.log','database-wasm-patched.log','database-browser-result.json','database-browser.png']
    for name in extras:copy(ROOT/'.build'/name,name)
    for package in ['asset','transport']:
        for kind in ['analysis','tests']:copy(Path('/tmp/smartdoc-'+package+'-'+kind+'.log'),'packages/'+package+'-'+kind+'.log')
    copy(ROOT/'.build/database-browser/index.html','database-runtime/index.html')
    binary=[{'file':p.name,'bytes':p.stat().st_size,'sha256':digest(p)} for p in sorted((ROOT/'.build/database-browser').glob('muse_database*'))]
    (destination/'database-runtime/artifacts.json').write_text(json.dumps(binary,indent=2)+'\n')
    cloud=WORKSPACE/'Muse-Server/AppFlowy-Cloud'
    patch_files=['src/api/file_storage.rs','src/api/mod.rs','src/api/workspace.rs','services/appflowy-collaborate/src/group/group_init.rs']
    patch=subprocess.check_output(['git','-C',str(cloud),'diff','--',*patch_files],text=True)
    (destination/'cloud-owned.patch').write_text(patch)
    copy(cloud/'src/api/private_assets.rs','cloud-private-assets.rs')
    owned=[]
    for folder in ['rust/src','flutter/lib','flutter/test','flutter/example/lib','flutter/example/integration_test','flutter/web_example/lib','scripts']:
        owned.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ['.rs','.dart','.py'])
    for name in ['rust/Cargo.toml','rust/Cargo.lock','flutter/pubspec.yaml','flutter/pubspec.lock','flutter/example/pubspec.yaml','flutter/example/pubspec.lock','flutter/web_example/pubspec.yaml','flutter/web_example/pubspec.lock']:
        owned.append(ROOT/name)
    for folder in ['vendor/appflowy_editor','vendor/appflowy_collab','probes/database_runtime/vendor/collab-database']:
        owned.extend(ROOT/folder/name for name in ['openmuse-upstream.json','upstream-files.json','openmuse.patch'])
    owned.extend(ROOT/'probes/database_runtime'/name for name in ['Cargo.toml','Cargo.lock','src/lib.rs','README.md'])
    for folder in ['packages/muse_asset_contract','packages/muse_appflowy_transport','packages/muse_collab_contract','plugins/smart-document']:
        package=WORKSPACE/'Muse-Client'/folder
        owned.extend(p for part in ['lib','test'] for p in (package/part).rglob('*.dart'))
        owned.extend(package/name for name in ['pubspec.yaml','pubspec.lock'] if (package/name).is_file())
    owned.extend(cloud/name for name in [*patch_files,'src/api/private_assets.rs'])
    owned.append(DOCS/'scripts/verify_media_evidence.py')
    lock={'date':datetime.now(timezone.utc).isoformat(),'mode':'working-tree increment, not a clean multi-repository release','files':[
        {'path':str(p.relative_to(WORKSPACE)),'sha256':digest(p)} for p in sorted(set(owned))]}
    (destination/'source-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    full=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True)
    assert full.returncode==1
    (destination/'full-parity-gate.log').write_text(full.stdout+full.stderr)
    result={'phase':'P6-20261106','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun',
      'slices':{'rustTests':17,'flutterTests':24,'appleUiChecksPerPlatform':7,'appleFreshProcessChecksPerPlatform':4,'browserChecks':10,'browserReloadChecks':3,'nativeReadbackChecks':6,'privateAssetHttpGroups':8,'neutralAssetTests':1,'neutralTransportTests':2},
      'fullParityGate':{'status':'rejected-expected','exitCode':1},'remaining':['complete SiYuan editing and database semantics/UI','WebSocket presence/relative selections','durable ACK and server domain validation on all ingress','revocation/share/private comments/history','Agent/Office collaboration and production Host release'],
      'limits':['Apple image pickers used injected synthetic input; actual browser filechooser independently exercised','runtime database qualification is not database product/UI acceptance','Android not installed under persistent user instruction']}
    (destination/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    superseded=[('media-runs/20261106T032257Z-media-04a9e7e1d76d','ios-hit-test',['result.json','media_document_test.dart.log']),
                ('media-runs/20261106T032455Z-media-1e8fdfe6eea9','ios-intermediate-build',['result.json','media_reopen_test.dart.log'])]
    for folder,label,names in superseded:
        for name in names:copy(ROOT/'.build'/folder/name,'superseded/'+label+'/'+name)
    copy(ROOT/'.build/phase2/20261106T033046Z/native-readback.log','superseded/native-readback-assumed-text-last.log')
    (destination/'README.zh-CN.md').write_text('''# P6 增量验收证据

macOS/iOS 各 7 项 UI 与协作检查、4 项无凭据新进程重开；Web 10 项、整页重载 3 项、原生读回 6 项。浏览器真实文件选择器另有第二用户原生读回及截图。Apple 图片输入使用合成适配器，不冒充系统选择器或相册验证。

superseded 保留早期命中/中间编译/末块断言失败；当前结果以 macos、ios 和 web-regression 下的通过回执为准。图片截屏已等待实际解码帧，尺寸已验证实际渲染宽度。数据库仅为原内核运行资格，未交付数据库产品 UI。

本文与 result.json 仅记录本批增量。完整思源/协作门仍拒绝完成，Android 未运行，正式 Host 未发布。生产凭据、fixture tokens、定义文件和私有用户参考画面均不归档。
''')
    manifest={'files':[{'path':str(p.relative_to(destination)),'bytes':p.stat().st_size,'sha256':digest(p)} for p in sorted(destination.rglob('*')) if p.is_file()]}
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'P6 increment archived: {len(manifest["files"])} artifacts, {len(lock["files"])} source fingerprints; full product NOT COMPLETE')
if __name__=='__main__':main()
