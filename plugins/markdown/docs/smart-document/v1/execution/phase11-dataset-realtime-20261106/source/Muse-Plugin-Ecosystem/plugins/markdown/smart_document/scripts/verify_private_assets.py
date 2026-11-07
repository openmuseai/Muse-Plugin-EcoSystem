#!/usr/bin/env python3
"""Exercise actual original Cloud bucket storage and every legacy bypass route.

Requires a fresh provisioned fixture and a source collab created by native-seed.
Only synthetic image bytes are uploaded; credentials stay in ignored fixture files.
"""
import base64
import hashlib
import json
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request
import uuid
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]


def main():
    fixture = json.loads((ROOT / '.build/e2e-fixture.json').read_text())
    origin, workspace, owner = fixture['origin'], fixture['workspaceId'], fixture['objectId']
    http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def png_chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
    pixels = b''.join(b'\x00' + b''.join(bytes((60, 110 if (x//8+y//8)%2 else 190, 220, 255)) for x in range(32)) for y in range(32))
    image = b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('!IIBBBBB', 32, 32, 8, 6, 0, 0, 0)) + png_chunk(b'IDAT', zlib.compress(pixels)) + png_chunk(b'IEND', b'')
    image_path = ROOT / '.build/fixtures/private-image.png'
    image_path.parent.mkdir(exist_ok=True)
    image_path.write_bytes(image)
    digest = hashlib.sha256(image).hexdigest()
    parent = 'muse-private-object-' + owner
    private = f'/api/file_storage/{workspace}/private/{owner}/blob/{digest}'
    checks = []

    def request(method, route, user=None, body=None, mime=None):
        headers = {}
        if user: headers['Authorization'] = 'Bearer ' + fixture['users'][user]['accessToken']
        if mime: headers['Content-Type'] = mime
        req = urllib.request.Request(origin + route, data=body, headers=headers, method=method)
        try:
            with http.open(req, timeout=15) as response:
                return response.status, response.read(), dict(response.headers)
        except urllib.error.HTTPError as error:
            return error.code, error.read(), dict(error.headers)

    def denied(method, route, user=None, body=None, mime=None, expected_code=None):
        status, raw, _ = request(method, route, user, body, mime)
        if expected_code is not None:
            assert json.loads(raw).get('code') == expected_code, 'Private namespace guard was not reached'
        if status == 200:
            try:
                data = json.loads(raw)
                assert isinstance(data, dict) and data.get('code') not in (None, 0), 'Legacy route accepted private object'
            except ValueError:
                raise AssertionError('Private bytes exposed by an alternate route')

    status, body, _ = request('PUT', private, 'alice', image, 'image/png')
    assert status == 200, f'Private upload failed: HTTP {status}'
    reference = json.loads(body)
    assert reference['key'] == digest and reference['owner'] == owner and reference['byte_length'] == len(image)
    checks.append('authenticated-object-scoped-upload-reuses-original-cloud-bucket')
    status, body, headers = request('GET', private, 'bob')
    assert status == 200 and body == image
    assert headers.get('cache-control', headers.get('Cache-Control')) == 'private, no-store'
    checks.append('second-authenticated-member-reads-identical-private-bytes-with-no-public-cache')
    denied('GET', private)
    denied('GET', private, 'outsider')
    denied('PUT', private, 'outsider', image, 'image/png')
    checks.append('anonymous-and-nonmember-read-write-rejected')
    legacy = [f'/api/file_storage/{workspace}/v1/blob/{parent}/{digest}',
              f'/api/file_storage/{workspace}/blob/' + urllib.parse.quote(parent + '/' + digest, safe=''),
              f'/api/file_storage/{workspace}/v1/metadata/{parent}/{digest}',
              f'/api/file_storage/{workspace}/metadata/{parent}_{digest}']
    for route in legacy:
        denied('GET', route, expected_code=-2)
        denied('GET', route, 'alice', expected_code=-2)
    checks.append('legacy-v0-v1-encoded-slash-and-metadata-read-bypasses-rejected')
    denied('PUT', f'/api/file_storage/{workspace}/v1/blob/{parent}', 'alice', image, 'image/png', expected_code=-2)
    denied('PUT', legacy[1], 'alice', image, 'image/png', expected_code=-2)
    denied('DELETE', legacy[0], 'alice', expected_code=-2)
    denied('DELETE', legacy[1], 'alice', expected_code=-2)
    for action in ['create_upload', 'complete_upload']:
        denied('POST' if action == 'create_upload' else 'PUT', f'/api/file_storage/{workspace}/{action}', 'alice',
               json.dumps({'parent_dir': parent, 'file_id': digest, 'upload_id': 'synthetic', 'parts': [], 'content_type': 'image/png'}).encode(), 'application/json', expected_code=-2)
    denied('PUT', f'/api/file_storage/{workspace}/upload_part/{parent}/{digest}/synthetic/1', 'alice', image, 'image/png', expected_code=-2)
    checks.append('legacy-upload-delete-and-multipart-bypasses-rejected')
    denied('PUT', private[:-64] + '0' * 64, 'alice', image, 'image/png')
    missing = str(uuid.uuid4())
    denied('PUT', f'/api/file_storage/{workspace}/private/{missing}/blob/{digest}', 'alice', image, 'image/png')
    checks.append('digest-mismatch-and-missing-source-object-rejected')
    status, body, _ = request('GET', f'/api/file_storage/{workspace}/blobs', 'alice')
    assert status == 200 and parent.encode() not in body
    checks.append('legacy-listing-does-not-disclose-private-asset-metadata')
    status, body, _ = request('PUT', private, 'alice', image, 'image/png')
    assert status == 200 and json.loads(body)['key'] == digest
    status, body, _ = request('GET', private, 'bob')
    assert status == 200 and body == image
    checks.append('content-addressed-retry-is-idempotent-and-original-bytes-remain-intact')
    result = {'status': 'passed', 'platform': 'original-cloud-http', 'checks': checks,
              'objectId': owner, 'workspaceId': workspace, 'assetSha256': digest,
              'fullProductAcceptance': 'not-complete'}
    path = ROOT / '.build/phase6-private-assets-result.json'
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('Private asset API: ' + str(len(checks)) + ' checks passed; ' + str(path))


if __name__ == '__main__':
    main()
