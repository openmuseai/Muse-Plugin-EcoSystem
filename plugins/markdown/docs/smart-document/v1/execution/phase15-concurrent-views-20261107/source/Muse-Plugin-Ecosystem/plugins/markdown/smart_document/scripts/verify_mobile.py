#!/usr/bin/env python3
"""Run the explicit Mobile slice and a fresh-process reopen; never install implicitly.

Requires an explicitly selected device. Cloud mode fails preflight if unavailable;
--local-only reports Cloud as unrun. All secrets remain in ignored mode-0600 files.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / 'flutter/example'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--device', required=True, help='Explicit Flutter device ID; installs the isolated test app')
    p.add_argument('--local-only', action='store_true')
    p.add_argument('--require-soft-keyboard', action='store_true')
    p.add_argument('--fixture', type=Path, default=ROOT / '.build/e2e-fixture.json')
    args = p.parse_args()
    run = 'mobile-' + uuid.uuid4().hex[:12]
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    dest = ROOT / '.build/mobile-runs' / (stamp + '-' + run)
    dest.mkdir(parents=True)
    defines = {'SMARTDOC_RUN': run, 'SMARTDOC_REQUIRE_CLOUD': not args.local_only, 'SMARTDOC_REQUIRE_SOFT_KEYBOARD': args.require_soft_keyboard}
    report = {'run': run, 'mode': 'local-only' if args.local_only else 'cloud', 'checks': []}
    try:
        if not args.local_only:
            fixture = json.loads(args.fixture.read_text())
            http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            for origin in [fixture['origin'], fixture['authOrigin']]:
                with http.open(origin + '/health', timeout=3) as response:
                    if response.status != 200:
                        raise RuntimeError('Cloud fixture preflight failed')
            defines.update({'SMARTDOC_ORIGIN': fixture['origin'], 'SMARTDOC_WORKSPACE': fixture['workspaceId'],
                            'SMARTDOC_ALICE_TOKEN': fixture['users']['alice']['accessToken'],
                            'SMARTDOC_BOB_TOKEN': fixture['users']['bob']['accessToken']})
        config = dest / 'defines.private.json'
        config.write_text(json.dumps(defines))
        os.chmod(config, 0o600)
        for test, marker in [('mobile_document_test.dart', 'SMARTDOC_MOBILE_RESULT='),
                             ('mobile_reopen_test.dart', 'SMARTDOC_MOBILE_REOPEN_RESULT=')]:
            log = dest / (test + '.log')
            with log.open('w') as stream:
                result = subprocess.run(['flutter', 'test', 'integration_test/' + test, '-d', args.device,
                    '--no-uninstall', '--dart-define-from-file=' + str(config)], cwd=EXAMPLE,
                    stdout=stream, stderr=subprocess.STDOUT, timeout=600)
            if result.returncode:
                raise RuntimeError(test + ' failed; inspect its local log')
            receipts = [line.split(marker, 1)[1] for line in log.read_text().splitlines() if marker in line]
            if len(receipts) != 1:
                raise RuntimeError('Missing or ambiguous Mobile receipt')
            receipt = json.loads(receipts[0])
            if receipt.get('status') != 'passed' or receipt.get('run') != run:
                raise RuntimeError('Wrong Mobile receipt')
            report['checks'].append(receipt)
        if report['checks'][0]['objectId'] != report['checks'][1]['objectId']:
            raise RuntimeError('Fresh process opened a different resource')
        if not args.local_only and report['checks'][0].get('cloud') != 'tested':
            raise RuntimeError('Cloud was not verified')
        report['status'] = 'passed-local-slice' if args.local_only else 'passed-cloud-slice'
        report['releaseAcceptance'] = 'not-complete'
    except Exception as error:
        # Do not print credentials, request bodies or fixture contents.
        report['status'] = 'failed'
        report['reason'] = type(error).__name__ + ': ' + str(error)[:240]
    (dest / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Mobile verification: ' + report['status'] + '; ' + str(dest / 'result.json'))
    if report['status'] == 'failed':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
