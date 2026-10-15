"""Run against a disposable market service: upload -> review -> catalog -> delist."""
import argparse
import hashlib
import io
import json
import uuid
import zipfile
from urllib.error import HTTPError
from urllib.request import Request, urlopen

parser = argparse.ArgumentParser()
parser.add_argument('--origin', required=True)
parser.add_argument('--developer-token', required=True)
parser.add_argument('--reviewer-token', required=True)
args = parser.parse_args()
origin = args.origin.rstrip('/')
leaf = 'flow-' + uuid.uuid4().hex[:12]

def call(path, method='GET', body=None, token=None):
    headers = {}
    if token: headers['Authorization'] = 'Bearer ' + token
    if isinstance(body, dict):
        body = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    with urlopen(Request(origin + path, data=body, method=method, headers=headers), timeout=20) as response:
        content = response.read()
        return response.status, json.loads(content) if response.headers.get_content_type() == 'application/json' else content

memory = io.BytesIO()
with zipfile.ZipFile(memory, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr('manifest.json', json.dumps({
        'manifest_version':'0.3','name':leaf,'version':'1.0.0',
        'server':{'type':'node','entry_point':'server/index.mjs'},
    }))
    archive.writestr('server/index.mjs', 'process.stdout.write("ready")')
bundle = memory.getvalue()
digest = hashlib.sha256(bundle).hexdigest()
package_path = '/packages/' + digest + '.mcpb'
try:
    call(package_path, 'PUT', bundle)
    raise AssertionError('unauthorized upload succeeded')
except HTTPError as error: assert error.code == 401
assert call(package_path, 'PUT', bundle, args.developer_token)[0] == 201
document = {
    'name':'io.openmuse/' + leaf,'version':'1.0.0','description':'Flow test',
    'packages':[{'registryType':'mcpb','identifier':origin+package_path,
                 'fileSha256':digest,'transport':{'type':'stdio'}}],
}
status, submission = call('/v0.1/publish','POST',document,args.developer_token)
assert status == 202
submission_id = submission['_meta']['submissionId']
def listed():
    return any(item['server']['name'] == document['name'] for item in call('/v0.1/servers')[1]['servers'])
assert not listed()
assert call('/internal/submissions/'+submission_id+'/approve','POST',{'note':'TCK passed'},args.reviewer_token)[1]['state'] == 'approved'
assert listed()
assert call(package_path)[1] == bundle
assert call('/internal/submissions/'+submission_id+'/delist','POST',{'note':'Flow test'},args.reviewer_token)[1]['state'] == 'delisted'
assert not listed()
try:
    call(package_path)
    raise AssertionError('delisted package downloadable')
except HTTPError as error: assert error.code == 404
assert call('/internal/submissions/'+submission_id+'/relist','POST',{'note':'Restore'},args.reviewer_token)[1]['state'] == 'approved'
assert listed()
print('market flow passed:', document['name'])
