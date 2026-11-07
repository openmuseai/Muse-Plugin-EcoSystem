#!/usr/bin/env python3
"""Isolated, loopback-only AppFlowy Cloud fixture; never resets the existing Muse stack."""
import argparse
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CLOUD = Path(__file__).resolve().parents[5] / 'Muse-Server/AppFlowy-Cloud'
STATE = ROOT / '.build/stack'
COMPOSE = ['docker', 'compose', '-f', str(ROOT / 'infra/compose.yml')]


def ready(url):
    try:
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(url, timeout=1) as response:
            return response.status == 200
    except Exception:
        return False


def tcp_ready(port, redis=False):
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=1) as connection:
            if redis:
                connection.sendall(b'*1\r\n$4\r\nPING\r\n')
                return connection.recv(64) == b'+PONG\r\n'
            return True
    except OSError:
        return False


def health():
    return {'cloud': ready('http://127.0.0.1:18000/health'),
            'auth': ready('http://127.0.0.1:19999/health'),
            'postgres': tcp_ready(15432), 'redis': tcp_ready(16379, redis=True),
            'storage': ready('http://127.0.0.1:19000/minio/health/ready')}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['start', 'stop', 'restart-cloud', 'status'])
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    pid_file = STATE / 'cloud.pid'
    if args.action in ('stop', 'restart-cloud'):
        if pid_file.exists():
            pid = int(pid_file.read_text())
            command = subprocess.run(['ps', '-p', str(pid), '-o', 'comm='], capture_output=True, text=True).stdout.strip()
            if command == str(CLOUD / 'target/debug/appflowy_cloud'):
                os.kill(pid, signal.SIGTERM)
                for _ in range(40):
                    if not ready('http://127.0.0.1:18000/health'):
                        break
                    time.sleep(.25)
            pid_file.unlink()
        if args.action == 'stop':
            subprocess.run(COMPOSE + ['stop'], check=True)
            return
    if args.action == 'status':
        print(json.dumps(health()))
        return
    if ready('http://127.0.0.1:18000/health'):
        if not pid_file.exists():
            raise SystemExit('Port 18000 belongs to an untracked service; refusing reuse')
        command = subprocess.run(['ps', '-p', pid_file.read_text().strip(), '-o', 'comm='],
                                 capture_output=True, text=True).stdout.strip()
        if command != str(CLOUD / 'target/debug/appflowy_cloud'):
            raise SystemExit('Port 18000 owner does not match the tracked Cloud process')
    # A healthy Cloud HTTP endpoint does not prove Redis/Auth/storage are alive.
    # Reconcile only this named compose project before returning "already running".
    subprocess.run(COMPOSE + ['up', '-d'], check=True)
    for _ in range(90):
        current = health()
        if all(current[key] for key in ['auth', 'postgres', 'redis', 'storage']):
            break
        time.sleep(.5)
    else:
        raise SystemExit('Isolated dependencies not ready; inspect compose logs')
    if ready('http://127.0.0.1:18000/health'):
        print('Isolated Cloud and dependencies ready on 18000')
        return
    env = {k: v for k, v in os.environ.items() if not k.startswith(('APPFLOWY_', 'MUSE_', 'GOTRUE_', 'AI_', 'OPENAI_', 'AZURE_'))}
    env.update({
        'APPFLOWY_DATABASE_URL': 'postgres://postgres:smartdoc-local-development@127.0.0.1:15432/smartdoc',
        'APPFLOWY_REDIS_URI': 'redis://127.0.0.1:16379',
        'APPFLOWY_GOTRUE_BASE_URL': 'http://127.0.0.1:19999',
        'APPFLOWY_GOTRUE_JWT_SECRET': 'smartdoc-stage1-isolated-local-jwt-secret-not-for-production',
        'APPFLOWY_APPLICATION_HOST': '127.0.0.1',
        'APPFLOWY_APPLICATION_PORT': '18000',
        'APPFLOWY_BASE_URL': 'http://127.0.0.1:18000',
        'APPFLOWY_WEB_URL': 'http://127.0.0.1:18080',
        'APPFLOWY_CORS_ALLOWED_ORIGIN': 'http://127.0.0.1:18080,http://localhost:18080,http://127.0.0.1:50940,http://127.0.0.1:50943,http://127.0.0.1:50944',
        'APPFLOWY_ACCESS_CONTROL': 'true',
        'APPFLOWY_S3_USE_MINIO': 'true',
        'APPFLOWY_S3_MINIO_URL': 'http://127.0.0.1:19000',
        'APPFLOWY_S3_ACCESS_KEY': 'smartdoc',
        'APPFLOWY_S3_SECRET_KEY': 'smartdoc-local-development',
        'APPFLOWY_S3_BUCKET': 'smartdoc-stage1',
        'APPFLOWY_COLLAB_GROUP_PERSISTENCE_INTERVAL': '1',
        'APPFLOWY_COLLAB_EDIT_STATE_MAX_SECS': '1',
        'RUST_LOG': 'warn',
        'NO_PROXY': 'localhost,127.0.0.1,::1',
    })
    with (STATE / 'cloud.log').open('ab') as log:
        proc = subprocess.Popen([str(CLOUD / 'target/debug/appflowy_cloud')], cwd=STATE, env=env,
                                stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    pid_file.write_text(str(proc.pid))
    for _ in range(120):
        if ready('http://127.0.0.1:18000/health'):
            print('Isolated AppFlowy Cloud ready: http://127.0.0.1:18000')
            return
        if proc.poll() is not None:
            raise SystemExit('Cloud exited; inspect smart_document/.build/stack/cloud.log')
        time.sleep(.5)
    raise SystemExit('Cloud startup deadline exceeded; inspect .build/stack/cloud.log')


if __name__ == '__main__':
    main()
