#!/usr/bin/env python3
"""Create synthetic users/workspace in the isolated local fixture; no email is sent."""
import json
import os
from pathlib import Path
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def request(origin, route, method='GET', token=None, body=None):
    headers = {'Content-Type': 'application/json', 'client-version': '0.16.5', 'device_id': 'smart-document-fixture'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(origin + route, data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers, method=method)
    try:
        with HTTP.open(req, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # Never log URLs containing token credentials or response bodies containing sessions.
        raise RuntimeError('Fixture HTTP status ' + str(error.code)) from None


def data(response):
    if response.get('code') != 0:
        raise RuntimeError('Fixture Cloud code ' + str(response.get('code')))
    return response.get('data')


def main():
    cloud = 'http://127.0.0.1:18000'
    auth = 'http://127.0.0.1:19999'
    run = uuid.uuid4().hex[:12]
    users = {}
    for name in ['alice', 'bob', 'outsider']:
        email = f'smartdoc-{name}-{run}@example.com'
        password = 'SmartdocLocal123!'
        request(auth, '/signup', 'POST', body={'email': email, 'password': password})
        signed = request(auth, '/token?grant_type=password', 'POST', body={'email': email, 'password': password})
        token = signed['access_token']
        data(request(cloud, '/api/user/verify/' + token))
        users[name] = {'accessToken': token, 'email': email}
    workspaces = data(request(cloud, '/api/workspace', token=users['alice']['accessToken']))
    workspace = workspaces[0]['workspace_id']
    data(request(cloud, f'/api/workspace/{workspace}/invite', 'POST', users['alice']['accessToken'],
                 [{'email': users['bob']['email'], 'role': 'Member', 'skip_email_send': True}]))
    invites = data(request(cloud, '/api/workspace/invite', token=users['bob']['accessToken']))
    invite = next(i for i in invites if i['workspace_id'] == workspace)
    data(request(cloud, '/api/workspace/accept-invite/' + invite['invite_id'], 'POST', users['bob']['accessToken']))
    result = {'origin': cloud, 'authOrigin': auth, 'workspaceId': workspace,
              'objectId': str(uuid.uuid4()), 'run': run, 'users': users}
    destination = ROOT / '.build/e2e-fixture.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2) + '\n')
    os.chmod(destination, 0o600)
    print('Synthetic collaboration fixture created; local credentials stored in ignored .build/e2e-fixture.json')


if __name__ == '__main__':
    main()
