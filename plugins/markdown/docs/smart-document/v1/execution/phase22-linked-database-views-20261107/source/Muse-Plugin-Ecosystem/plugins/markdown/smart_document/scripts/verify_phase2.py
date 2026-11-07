#!/usr/bin/env python3
"""Native regression + actual browser WASM/Cloud interoperability acceptance.

The browser action is intentionally performed through the review UI. Open the
printed loopback URL, click Start, then reload with ?reopen=1 and click Start.
The runner requires real receipts and native readback; no missing check is skipped.
"""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = Path(__file__).resolve().parents[5]
DOCS = ROOT.parent / 'docs/smart-document/v1'
CONTRACT = WORKSPACE / 'Muse-Client/packages/muse_collab_contract'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    run = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    evidence = ROOT / '.build/phase2' / run
    evidence.mkdir(parents=True)
    steps = []
    def execute(name, command, cwd=ROOT, env=None):
        print(name, flush=True)
        log = evidence / (name + '.log')
        start = time.monotonic()
        with log.open('w') as out:
            completed = subprocess.run(command, cwd=cwd, env={**os.environ, **(env or {})},
                                       stdout=out, stderr=subprocess.STDOUT)
        steps.append({'name': name, 'exitCode': completed.returncode,
                      'seconds': round(time.monotonic() - start, 2), 'log': log.name, 'sha256': sha(log)})
        (evidence / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        if completed.returncode:
            raise SystemExit(f'{name} failed; inspect {log}')
        return log

    execute('engineering-baseline', ['python3', str(DOCS / 'scripts/verify_engineering_baseline.py')])
    execute('contract-dependencies', ['dart', 'pub', 'get', '--enforce-lockfile'], CONTRACT)
    execute('contract-analysis', ['dart', 'analyze'], CONTRACT)
    execute('contract-tests', ['dart', 'test', '--reporter', 'expanded'], CONTRACT)
    execute('wasm-build', ['python3', str(ROOT / 'scripts/build_web_core.py')])
    execute('browser-dependencies', ['flutter', 'pub', 'get', '--enforce-lockfile'], ROOT / 'flutter/web_example')
    log = execute('native-regression', ['python3', str(ROOT / 'scripts/verify_phase1.py'), '--native'])
    lines = [line for line in log.read_text().splitlines() if line.startswith('Phase-one verification passed: ')]
    if not lines:
        raise SystemExit('Native regression did not return its evidence directory')
    native = Path(lines[-1].split(': ', 1)[1])
    for name in ['summary.json', 'cloud-e2e.json', 'native-e2e.json', 'native-editor.png', 'source-lock.json']:
        shutil.copy2(native / name, evidence / ('regression-' + name))
    execute('cross-platform-fixture', ['python3', str(ROOT / 'scripts/provision_e2e.py')])
    execute('native-seed', ['flutter', 'test', 'test/cross_platform_test.dart', '--reporter', 'expanded'], ROOT / 'flutter')
    fixture = json.loads((ROOT / '.build/e2e-fixture.json').read_text())
    nonce = uuid.uuid4().hex
    defines = ROOT / '.build/web-defines.json'
    defines.write_text(json.dumps({
        'SMARTDOC_ORIGIN': fixture['origin'], 'SMARTDOC_WORKSPACE': fixture['workspaceId'],
        'SMARTDOC_OBJECT': fixture['objectId'], 'SMARTDOC_RUN': fixture['run'],
        'SMARTDOC_ALICE_TOKEN': fixture['users']['alice']['accessToken'],
        'SMARTDOC_BOB_TOKEN': fixture['users']['bob']['accessToken'],
        'SMARTDOC_OUTSIDER_TOKEN': fixture['users']['outsider']['accessToken'],
        'SMARTDOC_ACCEPTANCE': True, 'SMARTDOC_EVIDENCE_NONCE': nonce,
    }))
    os.chmod(defines, 0o600)
    execute('browser-build', ['flutter', 'build', 'web', '--no-web-resources-cdn',
                             '--dart-define-from-file=' + str(defines)], ROOT / 'flutter/web_example')
    config = ROOT / '.build/web-server-config.json'
    config.write_text(json.dumps({'nonce': nonce}))
    os.chmod(config, 0o600)
    for name in ['web-e2e-result.json', 'web-reload-result.json']:
        (ROOT / '.build' / name).unlink(missing_ok=True)
    with (evidence / 'web-server.log').open('w') as out:
        server = subprocess.Popen(['python3', str(ROOT / 'scripts/serve_web_fixture.py'), '--config', str(config)],
                                  stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        time.sleep(.5)
        if server.poll() is not None:
            raise SystemExit('Web fixture could not bind its loopback port; existing services are not stopped')
        execute('browser-core-tests', ['flutter', 'test', '--platform', 'chrome', 'test/web_core_test.dart',
                                       '--reporter', 'expanded'], ROOT / 'flutter')
        print('BROWSER_ACTION_REQUIRED: http://127.0.0.1:18080/ ; click 开始验证', flush=True)
        browser_counts = []
        for name, minimum, url in [('web-e2e-result.json', 8, 'http://127.0.0.1:18080/'),
                                   ('web-reload-result.json', 2, 'http://127.0.0.1:18080/?reopen=1')]:
            print('WAITING_BROWSER_RECEIPT: ' + url, flush=True)
            result_path = ROOT / '.build' / name
            for _ in range(600):
                if server.poll() is not None:
                    raise SystemExit('Web fixture exited before browser acceptance')
                if result_path.exists():
                    break
                time.sleep(.5)
            else:
                raise SystemExit('Browser acceptance not run; no receipt: ' + name)
            report = json.loads(result_path.read_text())
            if report['status'] != 'passed' or len(report.get('checks', [])) < minimum:
                raise SystemExit('Browser acceptance failed: ' + name)
            shutil.copy2(result_path, evidence / name)
            browser_counts.append(len(report['checks']))
        execute('native-readback', ['flutter', 'test', 'test/cross_platform_test.dart', '--reporter', 'expanded'],
                ROOT / 'flutter', {'SMARTDOC_CROSS_MODE': 'verify'})
    except BaseException:
        server.terminate()
        raise
    for name in ['native-web-readback.json', 'wasm-artifacts.json', 'cross-platform-seed.json']:
        shutil.copy2(ROOT / '.build' / name, evidence / name)
    owned = []
    for folder, patterns in [(ROOT / 'rust/src', ['*.rs']), (ROOT / 'flutter/lib', ['*.dart']),
                             (ROOT / 'flutter/hook', ['*.dart']), (ROOT / 'flutter/test', ['*.dart']),
                             (ROOT / 'flutter/web_example/lib', ['*.dart']), (ROOT / 'scripts', ['*.py']),
                             (CONTRACT / 'lib', ['*.dart']), (CONTRACT / 'test', ['*.dart'])]:
        for pattern in patterns:
            owned += list(folder.rglob(pattern))
    for folder, names in [(ROOT, ['rust/Cargo.toml', 'rust/Cargo.lock', 'flutter/pubspec.yaml', 'flutter/pubspec.lock',
                                 'flutter/web_example/pubspec.yaml', 'flutter/web_example/pubspec.lock',
                                 'vendor/appflowy_collab/openmuse-upstream.json', 'vendor/appflowy_collab/upstream-files.json',
                                 'vendor/appflowy_collab/openmuse.patch']),
                          (CONTRACT, ['pubspec.yaml', 'pubspec.lock'])]:
        owned += [folder / name for name in names]
    lock = {'phase': 'SD-F2-20261105', 'run': run, 'createdAt': datetime.now(timezone.utc).isoformat(),
            'sourceFiles': [{'path': str(p.relative_to(WORKSPACE)), 'sha256': sha(p)} for p in sorted(set(owned))],
            'notes': 'Native source/Cloud locks additionally preserved in regression-source-lock.json. Synthetic credentials excluded.'}
    (evidence / 'source-lock.json').write_text(json.dumps(lock, indent=2) + '\n')
    (evidence / 'summary.json').write_text(json.dumps({'phase': 'SD-F2-20261105', 'status': 'passed',
        'run': run, 'steps': steps, 'browserChecks': browser_counts[0], 'reloadChecks': browser_counts[1], 'nativeReadbackChecks': len(json.loads((evidence / 'native-web-readback.json').read_text())['checks']),
        'limits': ['Browser workbench fixture, not production Host web composition', 'Flutter JS surface with real Rust WASM core',
                   'Mobile, manual IME, performance and full G0 not certified', 'HTTP exchange is not durable ACK']}, indent=2) + '\n')
    print('Phase-two verification passed: ' + str(evidence), flush=True)
    print('Review web fixture left running on 127.0.0.1:18080; PID recorded in .build/web-server.pid', flush=True)


if __name__ == '__main__':
    main()
