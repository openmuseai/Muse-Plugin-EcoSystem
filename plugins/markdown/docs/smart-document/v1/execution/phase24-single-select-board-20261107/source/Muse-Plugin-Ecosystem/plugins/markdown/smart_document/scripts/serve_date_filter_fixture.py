#!/usr/bin/env python3
"""Loopback-only Dataset realtime WASM review and bounded credential-free receipts."""
import json
import http.client
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / '.build/date_filter-web-public.json').read_text())
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(ROOT / 'flutter/web_example/build/date_filter-web'), **kw)
    def log_message(self, *a): pass
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()
    def _proxy(self):
        # Test-only, fixed loopback destination. No redirects, arbitrary URLs,
        # cross-workspace requests or credential-bearing request logs.
        prefix = '/api/workspace/'
        path = urlparse(self.path).path
        suffix = path[len(prefix):]
        if suffix.startswith('v1/'): suffix = suffix[3:]
        if not suffix.startswith(CONFIG['SMARTDOC_WORKSPACE'] + '/collab/'):
            self.send_error(403); return
        size = int(self.headers.get('Content-Length', '0'))
        if not 0 <= size <= 16 * 1024 * 1024: self.send_error(413); return
        body = self.rfile.read(size) if size else None
        headers = {k: v for k, v in self.headers.items() if k.lower() in {'authorization', 'device-id', 'client-version', 'content-type'}}
        connection = http.client.HTTPConnection('127.0.0.1', 18000, timeout=25)
        try:
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            data = response.read(16 * 1024 * 1024 + 1)
            if len(data) > 16 * 1024 * 1024: self.send_error(502); return
            self.send_response(response.status)
            self.send_header('Content-Type', response.getheader('Content-Type', 'application/octet-stream'))
            self.send_header('Content-Length', str(len(data)))
            self.end_headers(); self.wfile.write(data)
        finally: connection.close()
    def do_GET(self):
        if self.path.startswith('/api/workspace/'): self._proxy()
        else: super().do_GET()
    def do_POST(self):
        if self.path.startswith('/api/workspace/'): self._proxy(); return
        route = urlparse(self.path).path
        names = {f'/__date_filter/{kind}/{CONFIG["DATE_FILTER_NONCE"]}': f'date_filter-web-{kind}.json' for kind in ['result', 'reload', 'peer']}
        if route not in names or self.headers.get('Origin') not in {None, 'http://127.0.0.1:50946'}:
            self.send_error(403); return
        size = int(self.headers.get('Content-Length', '0'))
        if not 0 < size <= 32768: self.send_error(413); return
        try:
            data = json.loads(self.rfile.read(size))
            assert isinstance(data, dict) and set(data) == {'status', 'objectId', 'rowId', 'datasetObjectId', 'checks', 'platform', 'date','actor','fieldId'}
            assert data['status'] == 'passed' and data['objectId'] == CONFIG['DATE_FILTER_OBJECT'] and data['rowId'] == CONFIG['DATE_FILTER_ROW'] and data['datasetObjectId'] == CONFIG['DATE_FILTER_DATASET']
            assert data['actor'] in {'alice','bob'} and data['fieldId']==CONFIG['DATE_FILTER_FIELD']
            assert isinstance(data['checks'], list) and all(isinstance(c, str) and len(c) < 200 for c in data['checks'])
            (ROOT / '.build' / names[route]).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
        except (ValueError, AssertionError, KeyError): self.send_error(400); return
        self.send_response(204); self.end_headers()

if __name__ == '__main__':
    print('Date filters fixture http://127.0.0.1:50946', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 50946), Handler).serve_forever()
