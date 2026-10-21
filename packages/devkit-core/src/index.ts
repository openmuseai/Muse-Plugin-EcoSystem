import { createHash, randomUUID } from 'node:crypto'
import { promises as fs } from 'node:fs'
import path from 'node:path'
import { parse } from 'acorn'
import JSZip from 'jszip'

export const digest=(data:string|Uint8Array)=>createHash('sha256').update(data).digest('hex')
const slug=/^[a-z][a-z0-9-]{2,40}$/
export const sha=/^[a-f0-9]{64}$/
export type Dependency={alias:string,provider:{id:string,version:string,sha256:string},contract:any}
export function validateDependencies(deps:Dependency[]) {
 if(!Array.isArray(deps)||deps.length<1||deps.length>8)throw Error('CHOOSE_CAPABILITIES')
 const aliases=new Set<string>(),providers=new Map<string,string>()
 for(const d of deps){
  if(!slug.test(d.alias)||aliases.has(d.alias)||!d.provider?.id||!sha.test(d.provider.sha256)||!/^\d+\.\d+\.\d+$/.test(d.provider.version)||!d.contract?.operations?.readSnapshot||!d.contract.tools?.includes(d.contract.operations.readSnapshot))throw Error('INVALID_DEPENDENCY')
  const previous=providers.get(d.provider.id);if(previous&&previous!==d.provider.version+'/'+d.provider.sha256)throw Error('PROVIDER_VERSION_CONFLICT')
  aliases.add(d.alias);providers.set(d.provider.id,d.provider.version+'/'+d.provider.sha256)
 }
 return deps
}
export function validateCode(code:string){
 if(Buffer.byteLength(code)>128*1024)throw Error('CODE_TOO_LARGE')
 const ast=parse(code,{ecmaVersion:'latest',sourceType:'module'})
 if(!ast.body.some((n:any)=>n.type==='ExportNamedDeclaration'&&n.declaration?.id?.name==='run'))throw Error('EXPORT_ASYNC_RUN_REQUIRED')
 // The fixed runner executes browser modules only. It never executes project code in Node.
 return {valid:true,sha256:digest(code)}
}
const files=['main.js','devkit.project.json','devkit.lock.json','README.md']
export class DevkitCore {
 constructor(readonly root:string,readonly assets:string,readonly namespace='io.openmuse'){}
 private async project(id:string){
  if(!slug.test(id))throw Error('INVALID_PROJECT_ID')
  const root=await fs.realpath(this.root),dest=path.join(root,id)
  if((await fs.lstat(dest)).isSymbolicLink()||await fs.realpath(dest)!==dest)throw Error('SYMLINK_DENIED')
  return dest
 }
 private async file(id:string,name:string){
  if(!files.includes(name))throw Error('PROJECT_PATH_DENIED')
  const file=path.join(await this.project(id),name)
  if((await fs.lstat(file)).isSymbolicLink())throw Error('SYMLINK_DENIED')
  return file
 }
 async initialize(id:string,deps:Dependency[],host:any){
  if(!slug.test(id)||!sha.test(host?.implementation?.buildSha256))throw Error('EXACT_HOST_BUILD_REQUIRED')
  validateDependencies(deps)
  await fs.mkdir(this.root,{recursive:true})
  const root=await fs.realpath(this.root),temporary=path.join(root,'.creating-'+randomUUID())
  await fs.mkdir(temporary,{mode:0o700})
  try {
   const project={format:'openmuse-devkit-project/1',id,name:id,version:'0.1.0',namespace:this.namespace,capabilities:deps.map(d=>({alias:d.alias,contract:d.contract.id,version:d.contract.version})),features:{compare:{required:true,allOf:deps.map(d=>d.alias)}}}
   const lock={format:'openmuse-devkit-lock/1',host,dependencies:deps}
   const main=await fs.readFile(path.join(this.assets,'main.js'),'utf8')
   for(const [name,body] of Object.entries({'main.js':main,'devkit.project.json':JSON.stringify(project,null,2),'devkit.lock.json':JSON.stringify(lock,null,2),'README.md':'# '+id+'\nIndependent MCP Apps plugin. Edit main.js, validate, debug with real providers, then submit. No Host or provider source required.\n'}))await fs.writeFile(path.join(temporary,name),body,{flag:'wx',mode:0o600})
   // mkdir reserves the final name atomically; concurrent initialization cannot overwrite it.
   const destination=path.join(root,id);await fs.mkdir(destination,{mode:0o700})
   try {for(const name of files)await fs.rename(path.join(temporary,name),path.join(destination,name))}
   catch(error){await fs.rm(destination,{recursive:true,force:true});throw error}
   return {project:id,files}
  } finally {await fs.rm(temporary,{recursive:true,force:true})}
 }
 async list(){await fs.mkdir(this.root,{recursive:true});return {projects:(await fs.readdir(this.root,{withFileTypes:true})).filter(e=>e.isDirectory()&&slug.test(e.name)).map(e=>e.name)}}
 async read(id:string,name:string){const text=await fs.readFile(await this.file(id,name),'utf8');return {file:name,text,sha256:digest(text)}}
 private queues=new Map<string,Promise<unknown>>()
 async write(id:string,name:string,text:string,expected:string){
  const key=id+'/'+name,previous=this.queues.get(key)??Promise.resolve()
  const task=previous.catch(()=>{}).then(async()=>{
   if(Buffer.byteLength(text)>128*1024)throw Error('FILE_TOO_LARGE')
   const file=await this.file(id,name),current=await fs.readFile(file)
   if(digest(current)!==expected)throw Error('REVISION_CONFLICT')
   // Lock and project files can be inspected but require explicit dependency re-resolution to change.
   if(name!=='main.js'&&name!=='README.md')throw Error('GENERATED_FILE_READ_ONLY')
   const temp=file+'.'+randomUUID()+'.tmp';await fs.writeFile(temp,text,{mode:0o600});await fs.rename(temp,file)
   return {file:name,sha256:digest(text)}
  })
  this.queues.set(key,task)
  try{return await task}finally{if(this.queues.get(key)===task)this.queues.delete(key)}
 }
 async validate(id:string){return validateCode((await this.read(id,'main.js')).text)}
 async pack(id:string){
  const code=(await this.read(id,'main.js')).text,validation=validateCode(code)
  const project=JSON.parse((await this.read(id,'devkit.project.json')).text),lock=JSON.parse((await this.read(id,'devkit.lock.json')).text)
  validateDependencies(lock.dependencies)
  const sdk=await fs.readFile(path.join(this.assets,'client.js'),'utf8')
  const escaped=(value:any)=>JSON.stringify(value).replaceAll('<','\\u003c')
  const html=`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><style>body{margin:32px;font:16px system-ui;color:#182639;background:#f5f7fa}button{padding:12px 18px;margin:6px;border:1px solid #cad3de;border-radius:9px;background:white}pre{white-space:pre-wrap;background:white;padding:24px;border-radius:12px}#status{margin:14px 0}</style></head><body><h1>${id}</h1><p>独立 MCP Apps 插件 · 每份资料单独授权 · 不依赖 DevKit 运行</p><div id="choices"></div><button id="run">运行 / 比较全部资料</button><div id="status">正在连接 Host…</div><pre id="result">请选择已锁定的能力对应的资源。</pre><script>${sdk.replaceAll('</script','<\\/script')}</script><script type="module">
${code.replaceAll('</script','<\\/script')}
const client=new window.OpenMuseCapabilities();const deps=${escaped(lock.dependencies)},bound=new Map();let last=[];
const status=document.getElementById('status'),result=document.getElementById('result');
await client.connect();status.textContent='已连接。请选择全部资料后运行。';
for(const dep of deps){const button=document.createElement('button');button.textContent='选择 '+dep.alias+' · '+dep.contract.title;document.getElementById('choices').append(button);button.onclick=async()=>{try{status.textContent='查找已安装能力…';const providers=await client.providers();const provider=providers.find(p=>p.id===dep.provider.id&&p.sha256===dep.provider.sha256);if(!provider)throw Error('PROVIDER_UNAVAILABLE_OR_CHANGED');const contract=provider.contracts.find(c=>c.id===dep.contract.id&&c.version===dep.contract.version);if(!contract)throw Error('CONTRACT_INCOMPATIBLE');if(bound.has(dep.alias))await client.call('capabilities_release',{binding:bound.get(dep.alias).binding});const binding=await client.bind(provider,contract);bound.set(dep.alias,binding);button.textContent='已选择 '+dep.alias+' · '+binding.resourceTitle;status.textContent='已授权 '+dep.alias;}catch(error){status.textContent=String(error)}}}
document.getElementById('run').onclick=async()=>{try{if(bound.size!==deps.length)throw Error('请先选择全部资料');status.textContent='正在并行调用真实 Provider…';const api={readAll:async()=>{last=await Promise.all(deps.map(async dep=>({capability:dep.alias,snapshot:await client.invoke(bound.get(dep.alias).binding,dep.contract.operations.readSnapshot)})));return last}};const output=await run(api);if(last.length!==deps.length||last.some(d=>!Number.isInteger(d.snapshot.pageCount)||d.snapshot.pageCount<1))throw Error('REAL_PROVIDER_RESULT_REQUIRED');result.textContent=JSON.stringify(output,null,2);await client.call('record_run',{report:{status:'passed',codeSha256:${escaped(validation.sha256)},providers:deps.map((d,i)=>({...d.provider,pageCount:last[i].snapshot.pageCount,source:last[i].snapshot.source})),completedAt:new Date().toISOString()}});status.textContent='真实能力调试通过 · 已记录测试报告';}catch(error){status.textContent=String(error);result.textContent=String(error)}};
</script></body></html>`
  const manifest={manifest_version:'0.3',name:id,display_name:project.name,version:project.version,description:'Independent multi-resource capability plugin created with OpenMuse DevKit.',author:{name:'Plugin developer'},license:'MIT',compatibility:{platforms:['darwin'],runtimes:{node:'>=22.13.0'}},server:{type:'node',entry_point:'server.mjs',mcp_config:{command:'node',args:['${__dirname}/server.mjs']}}}
  const zip=new JSZip(),date=new Date('2020-01-01T00:00:00Z')
  const entries:any={'manifest.json':JSON.stringify(manifest),'index.html':html,'server.mjs':await fs.readFile(path.join(this.assets,'runtime.mjs')),'devkit/dependencies.json':JSON.stringify({profile:'openmuse-capabilities/1',dependencies:lock.dependencies.map(({alias,provider,contract}:Dependency)=>({alias,provider,contract}))}),'devkit/project.json':JSON.stringify(project),'LICENSE':'MIT; generated plugin code belongs to its developer. See bundled dependency licenses.\n','THIRD-PARTY-NOTICES.txt':await fs.readFile(path.join(this.assets,'THIRD-PARTY-NOTICES.txt'))}
  for(const [name,data]of Object.entries(entries))zip.file(name,data as any,{date,createFolders:false})
  const bytes=await zip.generateAsync({type:'nodebuffer',compression:'DEFLATE',compressionOptions:{level:6}})
  return {bytes,sha256:digest(bytes),project,codeSha256:validation.sha256,dependencies:lock.dependencies}
 }
 async record(id:string,report:any){
  const current=await this.pack(id)
  if(report.status!=='passed'||report.codeSha256!==current.codeSha256||!Array.isArray(report.providers)||report.providers.length!==current.dependencies.length)throw Error('TEST_REPORT_STALE_OR_INCOMPLETE')
  for(const dep of current.dependencies){const p=report.providers.find((p:any)=>p.id===dep.provider.id&&p.version===dep.provider.version&&p.sha256===dep.provider.sha256);if(!p||p.pageCount<1||typeof p.source!=='string')throw Error('TEST_PROVIDER_MISMATCH')}
  await fs.writeFile(path.join(await this.project(id),'test-report.json'),JSON.stringify({...report,bundleSha256:current.sha256,evidence:'development-client-report-not-server-attestation'}),{mode:0o600})
  return {accepted:true,sha256:current.sha256}
 }
 async submit(id:string,origin:string,token:string){
  const url=new URL(origin);if(url.protocol!=='https:'&&!(['127.0.0.1','localhost'].includes(url.hostname)&&url.protocol==='http:'))throw Error('HTTPS_REQUIRED')
  if(!token)throw Error('DEVELOPER_CREDENTIAL_REQUIRED')
  const packed=await this.pack(id),report=JSON.parse(await fs.readFile(path.join(await this.project(id),'test-report.json'),'utf8'))
  if(report.bundleSha256!==packed.sha256)throw Error('TEST_REPORT_STALE')
  const request=async(route:string,method:string,body:any,type:string)=>{
   const response=await fetch(new URL(route,url),{method,body,redirect:'error',signal:AbortSignal.timeout(90000),headers:{Authorization:'Bearer '+token,'Content-Type':type}})
   if(!response.ok)throw Error('MARKET_HTTP_'+response.status)
   return response.json() as any
  }
  await request('/v0.1/packages/'+packed.sha256+'.mcpb','PUT',packed.bytes,'application/octet-stream')
  const server={$schema:'https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json',name:this.namespace+'/'+id,title:id,version:packed.project.version,description:'Independent PPTX and PDF capability composition plugin. Desktop development candidate.',packages:[{registryType:'mcpb',identifier:new URL('/packages/'+packed.sha256+'.mcpb',url).href,fileSha256:packed.sha256,transport:{type:'stdio'}}]}
  const result=await request('/v0.1/publish','POST',JSON.stringify(server),'application/json')
  if(result._meta?.status!=='pending'||typeof result._meta?.submissionId!=='string')throw Error('INVALID_MARKET_RECEIPT')
  const receipt={submissionId:result._meta.submissionId,status:'pending',sha256:packed.sha256,name:server.name,version:server.version}
  await fs.writeFile(path.join(await this.project(id),'submission.json'),JSON.stringify(receipt),{mode:0o600})
  return receipt
 }
}
