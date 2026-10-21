import test from 'node:test'
import assert from 'node:assert/strict'
import {createServer} from 'node:http'
import {promisify} from 'node:util'
import {execFile} from 'node:child_process'
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import {pathToFileURL} from 'node:url'
import {DevkitCore} from '../../../packages/devkit-core/src/index.js'

test('shipped CLI refuses an old candidate report before fetching it after the bundle changes',async()=>{
 const directory=await mkdtemp(path.join(os.tmpdir(),'devkit-stale-run-'))
 const id='report-candidate',core=new DevkitCore(directory,path.resolve('plugins/developer-kit/dist/template'))
 let reads=0
 const server=createServer(async(req,res)=>{
  if(req.method!=='POST'){res.statusCode=405;res.end();return}
  let input='';for await(const data of req)input+=data
  const message=JSON.parse(input);res.setHeader('content-type','application/json')
  if(message.id===undefined){res.statusCode=202;res.end();return}
  let result:any={}
  if(message.method==='initialize')result={protocolVersion:'2025-11-25',serverInfo:{name:'Report fixture',version:'1.0.0'},capabilities:{tools:{}}}
  if(message.method==='tools/call'){
   if(message.params.name==='development_read_resource')reads++
   result={content:[],structuredContent:{roots:[{uri:pathToFileURL(directory+'/').href,name:'Fixture'}]}}
  }
  res.end(JSON.stringify({jsonrpc:'2.0',id:message.id,result}))
 })
 try{
  await core.initialize(id,[{alias:'slides',provider:{id:'test/slides',version:'1.0.0',sha256:'a'.repeat(64)},contract:{id:'https://example.org/slides',version:'1.0.0',operations:{readSnapshot:'read_snapshot'},tools:['read_snapshot']}}],{implementation:{buildSha256:'b'.repeat(64)}})
  const root=path.join(directory,id);await mkdir(path.join(root,'.devkit'))
  await writeFile(path.join(root,'.devkit/run.json'),JSON.stringify({runRef:'old-candidate',sha256:'0'.repeat(64)}))
  await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve))
  const port=(server.address() as any).port
  await assert.rejects(promisify(execFile)(process.execPath,[path.resolve('plugins/developer-kit/dist/cli.mjs'),'report'],{cwd:root,env:{...process.env,MCP_HOST_URL:`http://127.0.0.1:${port}/mcp`,MCP_HOST_TOKEN:'test-only'}}),error=>{
   assert.match((error as any).stderr,/TEST_RUN_STALE/);return true
  })
  assert.equal(reads,0,'must not relabel a report from a different immutable candidate')
 }finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));await rm(directory,{recursive:true,force:true})}
})
