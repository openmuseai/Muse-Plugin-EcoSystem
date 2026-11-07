#!/usr/bin/env python3
"""Loopback-only Dataset realtime WASM review and bounded credential-free receipts."""
import json
import uuid
import http.client
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / '.build/board-web-public.json').read_text())
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(ROOT / 'flutter/web_example/build/board-web'), **kw)
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
        if self.path.startswith('/api/workspace/'): self._proxy();return
        route=urlparse(self.path).path
        names={f'/__board/{kind}/{CONFIG["BOARD_NONCE"]}':f'board-web-{kind}.json' for kind in ['result','peer','reload']}
        if route not in names or self.headers.get('Origin') not in {None,'http://127.0.0.1:50946'}:self.send_error(403);return
        size=int(self.headers.get('Content-Length','0'))
        if not 0<size<=65536:self.send_error(413);return
        try:
            data=json.loads(self.rfile.read(size))
            assert isinstance(data,dict) and set(data)=={'status','actor','objectId','datasetObjectId','platform','checks','webViewId','webRowId','fieldId','numberFieldId','branch','history','views'}
            assert data['status']=='passed' and data['objectId']==CONFIG['BOARD_OBJECT'] and data['datasetObjectId']==CONFIG['BOARD_DATASET'] and data['fieldId']==CONFIG['BOARD_FIELD']
            assert data['actor'] in {'alice','bob'} and data['platform'] in {'web','web-reload'}
            assert isinstance(data['checks'],list) and 0<len(data['checks'])<=32 and all(isinstance(c,str) and len(c)<200 for c in data['checks'])
            for key in ['webViewId','webRowId','fieldId','numberFieldId']:uuid.UUID(data[key])
            branch=data['branch'];assert isinstance(branch,dict) and set(branch)<= {'viewCount','rowCount','heldFrames','httpHeld'} and all(type(v)==int and 0<=v<=1000 for v in branch.values())
            views=data['views'];assert isinstance(views,list) and len(views)==3 and len({v['id'] for v in views})==3
            assert {CONFIG['BOARD_FIRST'],CONFIG['BOARD_NATIVE'],data['webViewId']} == {v['id'] for v in views}
            for v in views:
                assert set(v)=={'id','layout','rowIds','groups'} and v['layout'] in {0,1};uuid.UUID(v['id'])
                assert isinstance(v['rowIds'],list) and len(v['rowIds'])==3 and len(set(v['rowIds']))==3
                for row in v['rowIds']:uuid.UUID(row)
                if v['groups'] is not None:
                    assert isinstance(v['groups'],list) and len(v['groups'])<=65
                    for group in v['groups']:
                        assert set(group)=={'id','rowIds'};uuid.UUID(group['id'])
                        assert isinstance(group['rowIds'],list) and set(group['rowIds'])<=set(v['rowIds'])
            assert isinstance(data['history'],list) and len(data['history'])<=32
            for event in data['history']:
                assert set(event)=={'action','applied','viewIds'} and event['action'] in {'undo','redo'} and type(event['applied'])==bool
                assert isinstance(event['viewIds'],list) and len(event['viewIds'])<=32
                for view in event['viewIds']:uuid.UUID(view)
            (ROOT/'.build'/names[route]).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
        except(ValueError,AssertionError,KeyError,TypeError,AttributeError):self.send_error(400);return
        self.send_response(204);self.end_headers()
if __name__=='__main__':
    print('Board fixture http://127.0.0.1:50946',flush=True)
    ThreadingHTTPServer(('127.0.0.1',50946),Handler).serve_forever()
