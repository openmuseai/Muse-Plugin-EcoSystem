#!/usr/bin/env python3
"""Loopback-only review server for built Flutter assets and sanitized test receipts."""
import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
PREFIX = '/assets/packages/openmuse_smart_document/assets/wasm/'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--nonce', default='')
    parser.add_argument('--config')
    args = parser.parse_args()
    nonce = json.loads(Path(args.config).read_text())['nonce'] if args.config else args.nonce
    if not nonce:
        raise SystemExit('A fixture receipt nonce is required')

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(ROOT / 'flutter/web_example/build/web'), **kw)

        def log_message(self, *a):
            pass

        def end_headers(self):
            self.send_header('Cache-Control', 'no-store')
            # Only public, credential-free WASM core assets are cross-origin readable.
            if urlparse(self.path).path.startswith(PREFIX):
                self.send_header('Access-Control-Allow-Origin', '*')
            super().end_headers()

        def do_GET(self):
            path = urlparse(self.path).path
            if path.startswith(PREFIX):
                name = path[len(PREFIX):]
                if name not in {'muse_smart_document.js', 'muse_smart_document_bg.wasm'}:
                    self.send_error(404)
                    return
                data = (ROOT / 'flutter/assets/wasm' / name).read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'application/wasm' if name.endswith('.wasm') else 'text/javascript')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            super().do_GET()

        def do_POST(self):
            origin = self.headers.get('Origin')
            outputs = {'/__stage2/result/' + nonce: 'web-e2e-result.json',
                       '/__stage2/reload/' + nonce: 'web-reload-result.json'}
            if self.path not in outputs or origin not in {None, 'http://127.0.0.1:18080'}:
                self.send_error(403)
                return
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 32768:
                self.send_error(413)
                return
            try:
                result = json.loads(self.rfile.read(size))
                assert isinstance(result, dict) and set(result) <= {'status', 'checks', 'error', 'date', 'platform'}
                assert result['status'] in {'passed', 'failed'}
                (ROOT / '.build' / outputs[self.path]).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
            except (ValueError, AssertionError, KeyError):
                self.send_error(400)
                return
            self.send_response(204)
            self.end_headers()

    print('SmartDocument web fixture: http://127.0.0.1:18080', flush=True)
    server = ThreadingHTTPServer(('127.0.0.1', 18080), Handler)
    (ROOT / '.build/web-server.pid').write_text(str(os.getpid()))
    server.serve_forever()


if __name__ == '__main__':
    main()
