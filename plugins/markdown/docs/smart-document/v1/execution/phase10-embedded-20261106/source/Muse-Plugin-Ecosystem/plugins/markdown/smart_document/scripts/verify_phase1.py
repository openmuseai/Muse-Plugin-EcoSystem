#!/usr/bin/env python3
"""Build and exercise the first-stage product against isolated, real Cloud services."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = Path(__file__).resolve().parents[5]
CLIENT = WORKSPACE / 'Muse-Client'
CLOUD = WORKSPACE / 'Muse-Server/AppFlowy-Cloud'
DOCS = ROOT.parent / 'docs/smart-document/v1'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--native', action='store_true', help='Also build and exercise the actual macOS application')
    parser.add_argument('--offline', action='store_true', help='Resolve Dart dependencies only from a previously populated cache')
    args = parser.parse_args()
    run = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    evidence = ROOT / '.build/verification' / run
    evidence.mkdir(parents=True)
    steps = []

    def execute(name, command, cwd=ROOT, env=None):
        print(name, flush=True)
        log = evidence / (name + '.log')
        start = time.monotonic()
        with log.open('w') as out:
            result = subprocess.run(command, cwd=cwd, env={**os.environ, **(env or {})}, stdout=out, stderr=subprocess.STDOUT)
        steps.append({'name': name, 'exitCode': result.returncode,
                      'seconds': round(time.monotonic() - start, 2), 'log': log.name, 'sha256': digest(log)})
        (evidence / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        if result.returncode:
            raise SystemExit(f'{name} failed; inspect {log}')
        return log

    execute('product-baseline', ['python3', str(DOCS / 'scripts/verify_baseline.py')])
    execute('editor-source', ['python3', str(ROOT / 'scripts/verify_editor.py')])
    execute('rust-tests', ['cargo', 'test', '--locked', '--manifest-path', str(ROOT / 'rust/Cargo.toml')])
    pub_get = ['flutter', 'pub', 'get', '--enforce-lockfile'] + (['--offline'] if args.offline else [])
    execute('flutter-dependencies', pub_get, ROOT / 'flutter')
    execute('flutter-analysis', ['flutter', 'analyze'], ROOT / 'flutter')
    execute('flutter-local', ['flutter', 'test', 'test/controller_test.dart', 'test/realtime_projection_test.dart', 'test/editor_commands_test.dart',
                             'test/mobile_view_test.dart', 'test/document_view_test.dart', 'test/table_test.dart', 'test/asset_repository_test.dart', 'test/media_session_test.dart', 'test/embedded_document_test.dart',
                             '--concurrency', '1', '--timeout', '2m', '--reporter', 'expanded'], ROOT / 'flutter')
    execute('plugin-dependencies', pub_get, CLIENT / 'plugins/smart-document')
    execute('plugin-analysis', ['flutter', 'analyze'], CLIENT / 'plugins/smart-document')
    # Flutter may re-resolve SDK dev dependencies; do not leave its incidental
    # lock rewrite in the existing package's working tree, even on a failed test.
    contract_dir = CLIENT / 'packages/muse_resource_contract'
    contract_lock = contract_dir / 'pubspec.lock'
    previous_contract_lock = contract_lock.read_bytes() if contract_lock.exists() else None
    try:
        execute('old-contract-goldens', ['flutter', 'test', 'test/golden_contract_test.dart', '--reporter', 'expanded'], contract_dir)
    finally:
        if previous_contract_lock is None:
            contract_lock.unlink(missing_ok=True)
        else:
            contract_lock.write_bytes(previous_contract_lock)
    execute('cloud-build', ['cargo', 'build', '--locked', '-p', 'appflowy-cloud', '--features', 'use_actix_cors'], CLOUD, {'SQLX_OFFLINE': 'true'})
    execute('isolated-stack', ['python3', str(ROOT / 'scripts/dev_stack.py'), 'restart-cloud'])
    execute('fixture', ['python3', str(ROOT / 'scripts/provision_e2e.py')])
    execute('cloud-e2e', ['flutter', 'test', 'test/cloud_e2e_test.dart', 'test/cloud_deletion_test.dart', 'test/realtime_cloud_test.dart', 'test/realtime_permissions_cloud_test.dart', '--concurrency', '1', '--reporter', 'expanded'], ROOT / 'flutter')
    shutil.copy2(ROOT / '.build/cloud-e2e-result.json', evidence / 'cloud-e2e.json')
    if args.native:
        fixture = json.loads((ROOT / '.build/e2e-fixture.json').read_text())
        defines = ROOT / '.build/native-defines.json'
        defines.write_text(json.dumps({
            'SMARTDOC_ORIGIN': fixture['origin'], 'SMARTDOC_WORKSPACE': fixture['workspaceId'],
            'SMARTDOC_ALICE_TOKEN': fixture['users']['alice']['accessToken'],
            'SMARTDOC_BOB_TOKEN': fixture['users']['bob']['accessToken'], 'SMARTDOC_RUN': fixture['run'] + '-native',
        }))
        os.chmod(defines, 0o600)
        execute('native-dependencies', pub_get, ROOT / 'flutter/example')
        execute('native-analysis', ['flutter', 'analyze'], ROOT / 'flutter/example')
        log = execute('native-e2e', ['flutter', 'test', 'integration_test/smart_document_test.dart', '-d', 'macos',
                    '--dart-define-from-file=' + str(defines), '--reporter', 'expanded'], ROOT / 'flutter/example')
        matches = re.findall(r'SMARTDOC_EVIDENCE_DIRECTORY=(.+)', log.read_text())
        if not matches:
            raise SystemExit('Native test did not return an evidence directory')
        source = Path(matches[-1].strip())
        for name in ['native-editor.png', 'native-e2e.json']:
            shutil.copy2(source / name, evidence / name)

    # Only task-owned source patches; user changes such as deploy.env are not copied.
    patches = {
        'cloud-permission-and-delete-set.patch': (CLOUD, ['src/api/workspace.rs', 'services/appflowy-collaborate/src/group/group_init.rs']),
    }
    for name, (repo, files) in patches.items():
        (evidence / name).write_bytes(subprocess.check_output(['git', '-C', str(repo), 'diff', '--binary', '--', *files]))
    owned = list((ROOT / 'rust/src').rglob('*.rs')) + list((ROOT / 'flutter/lib').rglob('*.dart'))
    owned += list((ROOT / 'flutter/hook').rglob('*.dart')) + list((CLIENT / 'plugins/smart-document/lib').rglob('*.dart'))
    owned += list((ROOT / 'flutter/test').rglob('*.dart')) + list((ROOT / 'flutter/example/lib').rglob('*.dart'))
    owned += list((ROOT / 'flutter/example/integration_test').rglob('*.dart')) + list((ROOT / 'scripts').glob('*.py'))
    owned += [ROOT / x for x in ['rust/Cargo.toml', 'rust/Cargo.lock', 'flutter/pubspec.yaml', 'flutter/pubspec.lock',
                                'flutter/example/pubspec.yaml', 'flutter/example/pubspec.lock', 'infra/compose.yml', 'infra/images.lock.json',
                                'vendor/appflowy_editor/openmuse-upstream.json', 'vendor/appflowy_editor/upstream-files.json',
                                'vendor/appflowy_editor/openmuse.patch']]
    owned += list((ROOT / 'flutter/example/macos').rglob('*.entitlements'))
    owned += [CLIENT / 'plugins/smart-document' / x for x in ['pubspec.yaml', 'pubspec.lock']]
    owned += [CLOUD / x for x in ['src/api/workspace.rs', 'services/appflowy-collaborate/src/group/group_init.rs']]
    owned = sorted(set(owned))
    lock = {'phase': 'SD-F1-20261105', 'createdAt': datetime.now(timezone.utc).isoformat(),
            'collabRevision': 'e59260e524f33104b0ddcd6bb8f6218cad0f7e18',
            'editorRevision': '470c4e77c71b63f693ce0923a927afcd667d6f3b',
            'repositories': {str(p.relative_to(WORKSPACE)): subprocess.check_output(['git', '-C', str(p), 'rev-parse', 'HEAD'], text=True).strip()
                             for p in [WORKSPACE / 'Muse-Plugin-Ecosystem', CLIENT, CLOUD]},
            'toolchains': {name: subprocess.check_output(command, text=True).strip() for name, command in
                           [('rustc', ['rustc', '--version']), ('flutter', ['flutter', '--version'])]},
            'sourceFiles': [{'path': str(p.relative_to(WORKSPACE)), 'sha256': digest(p)} for p in owned],
            'cloudBinarySha256': digest(CLOUD / 'target/debug/appflowy_cloud'),
            'notes': 'Working-tree delivery. Hashes and explicit Cloud patch accompany HEADs; unrelated user changes are not archived. This is not a clean multi-repository release commit.'}
    (evidence / 'source-lock.json').write_text(json.dumps(lock, indent=2) + '\n')
    summary = {'phase': 'SD-F1-20261105', 'status': 'passed', 'native': args.native, 'steps': steps,
               'limits': ['Full product AC groups remain partial/unrun', 'Web/Mobile artifacts and manual IME not certified',
                          'Production Host release composition is not enabled', 'Full-sync HTTP exchange is not a durable ACK']}
    (evidence / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('Phase-one verification passed: ' + str(evidence), flush=True)


if __name__ == '__main__':
    main()
