#!/usr/bin/env python3
"""Freeze P12 qualified dates/contextual history evidence and owned source."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
WORKSPACE=ROOT.parents[3]
DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['macos','ios','bridge-macos']: parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    dest=DOCS/'execution/phase12-dates-20261106'
    if dest.exists(): raise SystemExit('Preserve existing immutable archive')
    stage=Path(tempfile.mkdtemp(prefix='dates-archive-',dir=ROOT/'.build'))
    def copy(src,name):
        assert src.is_file() and not src.is_symlink(),src
        if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt','.js'}:
            content=src.read_text()
            assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',content),src
            assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',content),src
        target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
    for platform in ['macos','ios','bridge_macos']:
        folder=getattr(args,platform).resolve()
        assert folder.is_relative_to((ROOT/'.build/dates-runs').resolve())
        report=json.loads((folder/'result.json').read_text())
        count=6 if platform=='bridge_macos' else 7
        assert report['status']=='passed-dates-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(count,3)
        names=['result.json','dates-e2e.json','dates-reopen.json','dates-editor.png','dates-dialog.png','dates-conflict.png',
               'dates_document_test.dart.log','dates_reopen_test.dart.log']
        if platform!='bridge_macos': names.append('dates-calendar.png')
        for name in names: copy(folder/name,platform+'/'+name)
    names=['p12-date-rust-tests-final.log','p12-dataset-local-final.log','p12-document-local.log','p12-dates-interaction-final.log',
      'p12-document-analysis.log','p12-dataset-analysis-final.log','p12-example-analysis-final.log','p12-dates-web-analysis-final.log',
      'p12-dataset-sdk-analysis.log','p12-dataset-sdk-tests.log','p12-native-keyboard-2.log',
      'p12-dates-wasm-build-final.log','p12-dates-web-build-final.log','dataset-wasm-artifacts.json',
      'p12-vendor-verification.log','p12-product-baseline.log','p12-dates-cloud-restart.log',
      'dates-web-public.json','dates-web-result.json','dates-web-peer.json','dates-web-reload.json',
      'dates-native-web-readback.json','p12-dates-native-web-readback.log',
      'dates-web-alice.png','dates-web-bob.png','dates-web-reopen.png','dates-web-conflict.png','dates-web-dialog.png',
      'dates-web-alice.ax.txt','dates-web-bob.ax.txt','dates-web-reopen.ax.txt','dates-web-conflict.ax.txt','dates-web-dialog.ax.txt',
      'dates-web-keyboard-undo.ax.txt','dates-web-keyboard-redo.ax.txt']
    for name in names: copy(ROOT/'.build'/name,name)
    for name in ['muse_dataset_core.js','muse_dataset_core_bg.wasm']:
        copy(ROOT/'dataset/flutter/assets/wasm'/name,'runtime-artifacts/'+name)
    # Preserve the observed visual defect and failed/cancelled diagnostics;
    # none of these are promoted into successful UI receipts.
    old=ROOT/'.build/dates-runs/20261106T153224Z-dates-ed1ed8b160d3'
    copy(old/'dates-dialog.png','diagnostic/ios-input-before-layout-fix.png')
    for f in (ROOT/'.build').glob('p12-keyboard-test*.log'): copy(f,'diagnostic/'+f.name)
    copy(ROOT/'.build/p12-native-keyboard.log','diagnostic/native-missing-material-localizations.log')
    spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py')
    prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior)
    owned=sorted(set(prior.owned_files()+[DOCS/'35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md',DOCS/'scripts/verify_dates_evidence.py']))
    lock={'date':datetime.now(timezone.utc).isoformat(),'mode':'owned working source snapshot; not a clean multi-repository release',
      'files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]}
    for f in owned: copy(f,'source/'+str(f.relative_to(WORKSPACE)))
    (stage/'source-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    binary=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text())
    assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==binary['sha256']
    (stage/'cloud-binary.json').write_text(json.dumps({**binary,'source':'P8 owned Cloud binary unchanged in P12; exact loopback CORS origin 50944 added'},indent=2)+'\n')
    gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True)
    assert gate.returncode==1 and 'Parity ledger valid' in gate.stdout
    (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
    report={'phase':'P12-20261106','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun',
      'slices':{'datasetRustTests':14,'datasetLocalUniqueChecks':25,'documentLocalChecks':32,'resourceSdkChecks':3,
        'macosKeyboardIntegrationGroups':1,'appleDateUiChecksPerPlatform':7,'appleFreshProcessChecksPerPlatform':3,
        'bridgeMacosChecksBeforeFinalPickerUi':6,'webAliceChecks':9,'webBobChecks':7,'webReloadChecks':5,'nativeWebReadbackChecks':4},
      'limits':['7 basic field types and one Grid; full 18 SiYuan field types/5 views remain open',
        'date storage is upstream second precision; SiYuan millisecond import, formats/lunar/reminders/calendar remain open',
        'original per-key Cell merging is not an atomic composite-date conflict protocol or character-level cell editing',
        'web AX keyboard redo qualified after explicitly restoring focus to the child control; continuous physical input not certified',
        'production Host registry/inherited grants, distributed immediate revoke, UID multi-device roster, scoped wire subscription and durable ACK remain open',
        'physical IME/keyboard geometry, Android, comments/history/Agent/Office and remaining SiYuan editing remain open'],
      'fullParityGate':{'status':'rejected-expected','exitCode':1}}
    (stage/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    (stage/'README.zh-CN.md').write_text('# P12 原日期字段与嵌入键盘边界\n\n原 DateTypeOption/DateCellData、独立 Root 1/Row 4 和 WS2。Rust 14 项，Dataset 本地 25 个独立用例，正文 32 项，公共 SDK 3 项；macOS/iOS 各 7 项 UI、3 项无凭据新进程。\n\n浏览器 Alice 9、Bob 7、IndexedDB 恢复 5、原生读回 4。bridge_macos 是浏览器继续编辑的实际对象来源（6 项，早于最终选择器 UI）；macos/ios 为最终 UI/source 回归。diagnostic 保留输入宽度缺陷及失败/取消记录，不计验收通过。source 为自有源码快照，runtime-artifacts 保存已核验的日期 WASM/glue。完整思源/协作门仍拒绝，Android 未安装。\n\n![iOS 完整日期输入](ios/dates-dialog.png)\n![iOS 原日历选择器](ios/dates-calendar.png)\n![真实网页草稿冲突](dates-web-conflict.png)\n')
    manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]}
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    stage.rename(dest)
    print(f'P12 archived: {len(manifest["files"])} artifacts including {len(owned)} source snapshots; full product NOT COMPLETE')
if __name__=='__main__': main()
