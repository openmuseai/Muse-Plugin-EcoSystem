#!/usr/bin/env python3
"""Upload an immutable MCPB and submit it for review; never approves."""
import argparse,getpass,hashlib,json,os,zipfile
from pathlib import Path
from urllib.request import Request,urlopen
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('bundle',type=Path);p.add_argument('--registry',default='https://plugins.openmuseai.com');p.add_argument('--namespace',default='io.openmuse')
a=p.parse_args();token=os.environ.get('MARKET_DEVELOPER_TOKEN') or getpass.getpass('Developer token: ')
origin=a.registry.rstrip('/');data=a.bundle.read_bytes();sha=hashlib.sha256(data).hexdigest()
with zipfile.ZipFile(a.bundle) as z:manifest=json.loads(z.read('manifest.json'))
def send(route,method,body):
 request=Request(origin+route,data=body,method=method,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json' if method=='POST' else 'application/octet-stream'})
 with urlopen(request,timeout=120) as r:return json.load(r)
send('/v0.1/packages/'+sha+'.mcpb','PUT',data)
server={'$schema':'https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json','name':a.namespace+'/'+manifest['name'],'title':manifest.get('display_name',manifest['name']),'version':manifest['version'],'description':manifest['description'],'packages':[{'registryType':'mcpb','identifier':origin+'/packages/'+sha+'.mcpb','fileSha256':sha,'transport':{'type':'stdio'}}]}
r=send('/v0.1/publish','POST',json.dumps(server).encode())
print(json.dumps({'name':server['name'],'version':server['version'],'sha256':sha,'submissionId':r['_meta']['submissionId'],'status':r['_meta']['status']},indent=2))
