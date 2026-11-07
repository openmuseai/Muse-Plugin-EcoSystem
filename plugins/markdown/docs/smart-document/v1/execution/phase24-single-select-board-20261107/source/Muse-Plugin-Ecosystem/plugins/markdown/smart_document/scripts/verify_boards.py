#!/usr/bin/env python3
"""Explicit native board UI + real Cloud + credential-free fresh-process reopen."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

def scrub_logs(folder):
    for path in folder.glob('*.log'):
        content=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[REDACTED_TEST_TOKEN]', path.read_text())
        content=re.sub(r'(--DartDefines=|DART_DEFINES=)[A-Za-z0-9+/=_,-]{32,}', r'\1[REDACTED_TEST_DEFINES]', content)
        path.write_text(content)


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='macos or an explicitly selected iOS simulator/device; installs isolated fixture')
    args = parser.parse_args()
    # This slice is intentionally restricted to Apple targets. Android remains
    # unrun under the user's persistent iOS-only instruction.
    if args.device != 'macos':
        devices = json.loads(subprocess.check_output(['flutter', 'devices', '--machine'], text=True))
        if not any(d['id'] == args.device and d.get('targetPlatform', '').startswith('ios') for d in devices):
            raise SystemExit('Select macos or a connected iOS target; no Android install permitted by this runner')
    run = 'board-' + uuid.uuid4().hex[:12]
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    dest = ROOT / '.build/board-runs' / (stamp + '-' + run)
    dest.mkdir(parents=True)
    report = {'run': run, 'device': args.device, 'status': 'failed', 'fullProductAcceptance': 'not-complete', 'steps': []}
    try:
        fixture = json.loads((ROOT / '.build/e2e-fixture.json').read_text())
        defines = {'SMARTDOC_RUN': run, 'SMARTDOC_ORIGIN': fixture['origin'], 'SMARTDOC_WORKSPACE': fixture['workspaceId'],
                   'SMARTDOC_ALICE_TOKEN': fixture['users']['alice']['accessToken'], 'SMARTDOC_BOB_TOKEN': fixture['users']['bob']['accessToken']}
        primary = dest / 'defines.private.json'
        primary.write_text(json.dumps(defines)); os.chmod(primary, 0o600)
        offline = dest / 'reopen.private.json'
        offline.write_text(json.dumps({'SMARTDOC_RUN': run})); os.chmod(offline, 0o600)
        for test, config, marker in [('board_document_test.dart', primary, 'SMARTDOC_BOARD_EVIDENCE='), ('board_reopen_test.dart', offline, 'SMARTDOC_BOARD_REOPEN=')]:
            log = dest / (test + '.log')
            with log.open('w') as stream:
                completed = subprocess.run(['flutter', 'test', 'integration_test/' + test, '-d', args.device, '--no-uninstall',
                    '--dart-define-from-file=' + str(config)], cwd=ROOT / 'flutter/example', stdout=stream, stderr=subprocess.STDOUT, timeout=600)
            scrub_logs(dest)
            report['steps'].append({'name': test, 'exitCode': completed.returncode})
            if completed.returncode: raise RuntimeError(test + ' failed; inspect its local log')
            matches = re.findall(re.escape(marker) + r'([^\r\n]+)', log.read_text())
            if len(matches) != 1: raise RuntimeError('Missing/ambiguous number evidence')
            source = Path(matches[0])
            for name in ['board-e2e.json','board-reopen.json','board-stale.png','board-cards.png','board-editor.png']:
                if (source / name).is_file(): shutil.copy2(source / name, dest / name)
        a = json.loads((dest / 'board-e2e.json').read_text())
        b = json.loads((dest / 'board-reopen.json').read_text())
        if a['status'] != 'passed' or b['status'] != 'passed' or a['run'] != run or b['run'] != run or a['objectId'] != b['objectId']:
            raise RuntimeError('Number receipt identity mismatch')
        report.update(status='passed-board-slice', platform=a['platform'], primaryChecks=len(a['checks']), freshProcessChecks=len(b['checks']))
    except Exception as error:
        report['reason'] = type(error).__name__ + ': ' + str(error)[:240]
    scrub_logs(dest)
    (dest / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Board verification: ' + report['status'] + '; ' + str(dest / 'result.json'))
    if report['status'] == 'failed': raise SystemExit(1)


if __name__ == '__main__':
    main()
