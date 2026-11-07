#!/usr/bin/env python3
"""Freeze P13 lifetime/authority regressions, actual UI and owned inputs."""
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
ROOT=Path(__file__).resolve().parents[1];WORKSPACE=ROOT.parents[3];DOCS=ROOT.parent/'docs/smart-document/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['macos','ios']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();dest=DOCS/'execution/phase13-lifecycle-20261107'
    if dest.exists():raise SystemExit('Preserve immutable prior evidence')
    stage=Path(tempfile.mkdtemp(prefix='lifecycle-archive-',dir=ROOT/'.build'))
    def copy(src,name):
        assert src.is_file() and not src.is_symlink(),src
        if src.suffix in {'.log','.json','.md','.rs','.dart','.py','.txt'}:
            s=src.read_text()
            assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',s),src
            assert not re.search(r'(?:--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}',s),src
        target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
    for platform in ['macos','ios']:
        folder=getattr(args,platform).resolve();assert folder.is_relative_to((ROOT/'.build/lifecycle-runs').resolve())
        r=json.loads((folder/'result.json').read_text());assert r['status']=='passed-lifecycle-slice' and (r['primaryChecks'],r['freshProcessChecks'])==(6,3)
        for name in ['result.json','lifecycle-e2e.json','lifecycle-reopen.json','lifecycle-editor.png',
                     'lifecycle_document_test.dart.log','lifecycle_reopen_test.dart.log']:copy(folder/name,platform+'/'+name)
    names=['p13-document-lifecycle-before.log','p13-dataset-lifecycle-before.log',
      'p13-document-lifecycle-qualified.log','p13-dataset-lifecycle-qualified.log','p13-document-local.log','p13-dataset-local.log',
      'p13-document-analysis.log','p13-dataset-analysis.log','p13-example-analysis-final.log',
      'p13-dataset-sdk-analysis.log','p13-dataset-sdk-tests.log','p13-document-sdk-analysis.log','p13-document-cloud.log',
      'p13-lifecycle-web-analysis-final.log','p13-lifecycle-web-build-final.log','p13-lifecycle-native-web-readback-final.log',
      'p13-vendor-verification.log','p13-product-baseline.log','p13-cloud-restart.log',
      'lifecycle-web-public.json','lifecycle-web-result.json','lifecycle-web-reload.json','lifecycle-native-web-readback.json',
      'lifecycle-web-editor.png','lifecycle-web-editor.ax.txt','lifecycle-web-closed.png','lifecycle-web-closed.ax.txt',
      'lifecycle-web-released.ax.txt','lifecycle-web-reopen.png','lifecycle-web-reopen.ax.txt',
      'lifecycle-web-row-timing.json','lifecycle-web-root-timing.json']
    for name in names:copy(ROOT/'.build'/name,name)
    copy(ROOT/'.build/lifecycle-web-deadline-diagnostic.ax.txt','diagnostic/manual-operation-exceeded-request-deadline.ax.txt')
    copy(ROOT/'.build/p13-document-sdk-tests.log','diagnostic/document-sdk-has-no-unit-test-files.log')
    spec=importlib.util.spec_from_file_location('prior',ROOT/'scripts/collect_dataset_realtime_evidence.py')
    prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior)
    owned=set(prior.owned_files())
    owned.update(DOCS/name for name in ['35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md','36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md',
                                     'scripts/verify_dates_evidence.py','scripts/verify_lifecycle_evidence.py'])
    # Keep the original binary input fixtures as well as text sources. Compiled
    # Flutter bundles containing synthetic credentials are deliberately excluded.
    for part in ['flutter/test/fixtures','dataset/flutter/test/fixtures','flutter/example/assets','flutter/web_example/assets']:
        owned.update(f for f in (ROOT/part).rglob('*')if f.is_file() and f.suffix in {'.png','.zst'})
    owned=sorted(owned)
    for f in owned:copy(f,'source/'+str(f.relative_to(WORKSPACE)))
    lock={'date':datetime.now(timezone.utc).isoformat(),'mode':'owned working source and fixture snapshot; not a clean multi-repository release',
          'files':[{'path':str(f.relative_to(WORKSPACE)),'sha256':sha(f)}for f in owned]}
    (stage/'source-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    binary=json.loads((DOCS/'execution/phase8-realtime-20261106/cloud-binary.json').read_text())
    assert sha(WORKSPACE/'Muse-Server/AppFlowy-Cloud/target/debug/appflowy_cloud')==binary['sha256']
    (stage/'cloud-binary.json').write_text(json.dumps({**binary,'source':'P8 Cloud binary unchanged; exact loopback CORS origin 50945 added for this fixture'},indent=2)+'\n')
    gate=subprocess.run(['python3',str(ROOT/'scripts/verify_parity.py'),'--require-complete'],capture_output=True,text=True)
    assert gate.returncode==1 and 'Parity ledger valid'in gate.stdout
    (stage/'full-parity-gate.log').write_text(gate.stdout+gate.stderr)
    report={'phase':'P13-20261107','status':'partial','fullProductAcceptance':'not-complete','parityCases':[],'android':'unrun',
      'slices':{'documentBeforeFailures':5,'datasetBeforeFailures':6,'documentLifecycleChecks':6,'datasetLifecycleChecks':8,
        'documentLocalUniqueChecks':38,'datasetLocalUniqueChecks':33,'datasetSdkChecks':3,'documentSdkUnitTests':'absent-not-counted',
        'documentActualCloudGroups':4,'appleUiChecksPerPlatform':6,'appleFreshProcessChecksPerPlatform':3,
        'webUiChecks':8,'webReloadChecks':4,'nativeWebReadbackChecks':4},
      'limits':['full SiYuan 18 fields/5 views and remaining editing features remain open; seven basic fields/one Grid are an increment',
        'client lifetime fencing is not a replacement for server ACL, distributed immediate revoke, durable ACK or offline commands',
        'production Host registry/session pooling/inherited grants, UID multi-device roster and scoped wire subscription remain open',
        'physical IME/soft-keyboard geometry, Android, comments/history/Agent/Office and full parity remain open'],
      'fullParityGate':{'status':'rejected-expected','exitCode':1}}
    (stage/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    (stage/'README.zh-CN.md').write_text('# P13 会话关闭与异步权限边界\n\n保留原文档 5 项、数据库 6 项失败复现。新增生命周期分别 6/8 项，本地完整组 38/33 项；Dataset SDK 3 项、原文档真实 Cloud 4 组。Document SDK 没有独立单测文件，不计通过；公开会话由实际应用路径验证。\n\nmacOS/iOS 各 6 项 UI、3 项无凭据新进程。macos 是网页继续编辑的同一实际对象来源；网页 8 项、IndexedDB 重开 4 项、Native 读回 4 项。响应来自原服务器，缓冲期间还没有发生传输超时，迟到成功/失败都必须遵守会话代次。\n\nsource 含自有源码及 PNG/zstd 测试输入。诊断日志不计为成功验收。生产 Host 统一资源目录/会话池、完整思源和协作门仍未通过，Android 未安装。\n\n![iOS 实际界面](ios/lifecycle-editor.png)\n![网页恢复后的编辑](lifecycle-web-editor.png)\n![网页关闭与迟到回包](lifecycle-web-closed.png)\n')
    manifest={'files':[{'path':str(f.relative_to(stage)),'bytes':f.stat().st_size,'sha256':sha(f)}for f in sorted(stage.rglob('*'))if f.is_file()]}
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');stage.rename(dest)
    print(f'P13 archived: {len(manifest["files"])} artifacts including {len(owned)} owned source/fixture snapshots; full product NOT COMPLETE')
if __name__=='__main__':main()
