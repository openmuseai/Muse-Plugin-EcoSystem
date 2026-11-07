#!/usr/bin/env python3
"""Archive the P9 selection-field increment; preserve prior baselines and open gates."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--macos',type=Path,required=True);p.add_argument('--ios',type=Path,required=True);args=p.parse_args()
    dest=DOCS/'execution/phase9-choices-20261106'
    if dest.exists():raise SystemExit('Preserve existing archive; never overwrite')
    def copy(src,relative):
        assert src.is_file() and not src.is_symlink(),src
        if src.suffix in {'.log','.json','.md','.rs','.dart','.py'}:
            s=src.read_text();assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',s),src
            assert '--DartDefines=' not in s,src
        target=dest/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
    for platform in ['macos','ios']:
        folder=getattr(args,platform).resolve();assert folder.is_relative_to((ROOT/'.build').resolve())
        report=json.loads((folder/'result.json').read_text());assert report['status']=='passed-choices-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(8,4)
        for name in ['result.json','choices-e2e.json','choices-reopen.json','choices-editor.png','choices_document_test.dart.log','choices_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
    names=['dataset-choice-core-tests.log','dataset-choice-final-all-analysis.log','dataset-choice-final-all-tests.log',
      'dataset-choice-transport-analysis.log','dataset-choice-transport-tests.log','dataset-choice-document-cloud-regression.log',
      'dataset-choice-wasm-build.log','dataset-wasm-artifacts.json','dataset-choice-web-analysis.log','dataset-choice-example-analysis.log',
      'dataset-choice-web-qualified-build.log','dataset-choice-semantics-final-tests.log','dataset-stale-http-after.log',
      'choices-web-public.json','choices-web-result.json','choices-web-reload.json','choices-native-web-readback.json',
      'dataset-choice-cloud-result.json','choices-web-single-panel.png','choices-web-multi-panel.png',
      'choices-web-create-field.png','choices-web-passed.png','choices-web-reopen.png']
    for name in names:copy(ROOT/'.build'/name,name)
    for name in ['dataset-choice-new-tests.log','dataset-choice-semantics-tests.log','dataset-choice-full-tests.log',
      'dataset-choice-native-readback-diagnostic.log','dataset-stale-http-before.log','dataset-choice-controller-read-timing.log','dataset-choice-read-timing.log']:
        copy(ROOT/'.build'/name,'superseded-or-diagnostic/'+name)
    # Working source scope is explicit and excludes caches, private definitions,
    # unrelated PDF/Word/Host modifications and production deployment settings.
    owned=[]
    for directory in ['rust','runtime','dataset','flutter/lib','flutter/hook','flutter/test','flutter/example/lib','flutter/example/integration_test','flutter/web_example/lib','scripts']:
        for f in (ROOT/directory).rglob('*'):
            rel=f.relative_to(ROOT/directory)
            if any(x in {'target','build','.dart_tool','__pycache__'} for x in rel.parts):continue
            if f.is_file() and (f.suffix in {'.rs','.dart','.py','.md'} or f.name in {'Cargo.toml','Cargo.lock','pubspec.yaml','pubspec.lock'}):owned.append(f)
    for directory in ['flutter','flutter/example','flutter/web_example']:
        owned.extend(ROOT/directory/name for name in ['pubspec.yaml','pubspec.lock'])
    for directory in ['vendor/appflowy_editor','vendor/appflowy_collab','vendor/appflowy_database','vendor/appflowy_proto']:
        owned.extend(ROOT/directory/name for name in ['openmuse-upstream.json','upstream-files.json','openmuse.patch'])
    for directory in ['packages/muse_appflowy_transport','packages/muse_appflowy_realtime','packages/muse_content_store','packages/muse_collab_contract','packages/muse_asset_contract','plugins/smart-document','plugins/dataset']:
        base=WORKSPACE/'Muse-Client'/directory
        owned.extend(f for part in ['lib','test','hook'] for f in (base/part).rglob('*.dart'))
        owned.extend(base/name for name in ['pubspec.yaml','pubspec.lock','README.zh-CN.md'] if (base/name).is_file())
    spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_realtime_evidence.py');prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior)
    cloud=WORKSPACE/'Muse-Server/AppFlowy-Cloud';owned.extend(cloud/name for name in prior.CLOUD_FILES)
    owned.extend(DOCS/name for name in ['32-PHASE9-DATABASE-FIELDS.zh-CN.md','scripts/verify_choices_evidence.py'])
    lock={'date':datetime.now(timezone.utc).isoformat(),'mode':'working-tree increment; not a clean multi-repository release',
      'files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)} for f in sorted(set(owned))]}
    (dest/'source-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    prior_binary=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text())
    assert sha(cloud/'target/debug/appflowy_cloud')==prior_binary['sha256'],'Unexpected Cloud binary change'
    (dest/'cloud-binary.json').write_text(json.dumps({**prior_binary,'source':'P8 unchanged owned Cloud implementation; P9 transport is client-side'},indent=2)+'\n')
    result={'phase':'P9-20261106','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun',
      'slices':{'datasetRustTests':9,'datasetFlutterChecks':17,'neutralTransportTests':5,'documentCloudTestGroups':4,
        'appleUiChecksPerPlatform':8,'appleFreshProcessChecksPerPlatform':4,'webChecks':7,'webReloadChecks':3,'nativeWebReadbackChecks':5},
      'limits':['6 basic field types/one Grid; complete 18 fields/5 views remain open','existing-option concurrent CRUD and full SiYuan color/description/import semantics unimplemented',
        'same-cell values use original atomic row-cell merge, not character/set merge','document embedding and Dataset realtime/presence adapters remain open',
        'immediate cross-instance revocation, durable ACK, comments/history/Agent/Office and full platform acceptance remain open'],
      'fullParityGate':{'status':'rejected-expected','exitCode':1}}
    (dest/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True)
    assert gate.returncode==1 and 'Parity ledger valid' in gate.stdout
    (dest/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
    (dest/'README.zh-CN.md').write_text('''# P9 单选/多选字段增量证据

复用原 Field/type-option/SelectOptionIds 和 cell writer，补齐稳定 ID、字段/原值前置条件、共享选择面板与单选/多选语义。macOS/iOS 各 8 项 UI、4 项新进程检查；浏览器 7/3，Native→Web→Native 同一对象往返 5 项。详见 [实施报告](../../32-PHASE9-DATABASE-FIELDS.zh-CN.md)。

保留错误地对 opaque bundle 查找明文的断言、语义句柄清理断言、原生 HTTP 读回失败及稳定复现的暂停/keep-alive 断开失败；修复只允许一次 GET 重试，POST 不自动重放。完整 SiYuan/协作门仍未通过，Android 未安装。
''')
    manifest={'files':[{'path':str(f.relative_to(dest)),'bytes':f.stat().st_size,'sha256':sha(f)} for f in sorted(dest.rglob('*')) if f.is_file()]}
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'P9 archived: {len(manifest["files"])} artifacts, {len(lock["files"])} source fingerprints; full product NOT COMPLETE')
if __name__=='__main__':main()
