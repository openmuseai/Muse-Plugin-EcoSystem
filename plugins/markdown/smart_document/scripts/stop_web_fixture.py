#!/usr/bin/env python3
"""Stop only the registered loopback review server; preserve data and other services."""
import argparse
import os
from pathlib import Path
import shlex
import signal
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    pid_file = root / '.build/web-server.pid'
    if not pid_file.exists():
        print('No registered review server')
        return
    pid = int(pid_file.read_text())
    command = subprocess.run(['ps', '-p', str(pid), '-o', 'args='], capture_output=True, text=True).stdout.strip()
    if not command:
        if not args.dry_run:
            pid_file.unlink()
        print('Registered review server has exited')
        return
    expected = str(root / 'scripts/serve_web_fixture.py')
    if expected not in shlex.split(command):
        raise SystemExit('PID does not belong to the task review server; refusing to stop it')
    if args.dry_run:
        print('Registered task review server verified; no action taken')
        return
    os.kill(pid, signal.SIGTERM)
    pid_file.unlink()
    print('Task review server stopped; browser storage and isolated Cloud preserved')


if __name__ == '__main__':
    main()
