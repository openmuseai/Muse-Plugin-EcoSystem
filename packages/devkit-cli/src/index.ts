import {fileURLToPath} from 'node:url'
import {promises as fs} from 'node:fs'
import path from 'node:path'
import {Client,StreamableHTTPClientTransport} from '@modelcontextprotocol/client'
import {DevkitCore} from '../../devkit-core/src/index.js'
import {randomUUID} from 'node:crypto'

async function regularFile(file:string){if(!(await fs.lstat(file)).isFile())throw Error('SYMLINK_OR_NON_FILE_DENIED')}
async function localDirectory(root:string,name:string){const directory=path.join(root,name);await fs.mkdir(directory,{mode:0o700}).catch((e:any)=>{if(e.code!=='EEXIST')throw e});if(!(await fs.lstat(directory)).isDirectory()||await fs.realpath(directory)!==directory)throw Error('SYMLINK_DENIED');return directory}
async function safeStateWrite(file:string,text:string){const exists=await fs.lstat(file).catch((e:any)=>{if(e.code!=='ENOENT')throw e;return null});if(exists&&!exists.isFile())throw Error('SYMLINK_OR_NON_FILE_DENIED');const temporary=file+'.'+randomUUID();try{await fs.writeFile(temporary,text,{flag:'wx',mode:0o600});await fs.rename(temporary,file)}finally{await fs.rm(temporary,{force:true})}}

export async function runCli(argv=process.argv.slice(2),environment=process.env){
 const [command,...args]=argv
 if(!command||command==='--help'||command==='help'){
  console.log('OpenMuse Plugin DevKit 0.3.3\n先在 OpenMuse 选择或新建 Workspace，再打开其终端。\n\n  muse search <关键词>                 搜索已安装与在线市场插件\n  muse install <插件ID>               请求 Host 安装已审核插件\n  muse init --name <名称> --capability <关键词或合同URI> [重复选择] [--template document-explainer]\n  muse check                          检查当前 Workspace 项目\n  muse dev                            在应用内运行候选包\n  muse report                         收集真实调试报告\n  muse pack                           生成不可变 MCPB\n  muse submit                         上传并进入市场待审\n\n初始化直接在当前目录生成文件，不新建隐藏的项目根目录，不覆盖已有文件。')
  return 0
 }
 if(!['search','install','init','check','dev','report','pack','submit'].includes(command))throw Error('未知 DevKit 命令；运行 muse --help')
 const options=new Map<string,string[]>()
 if(command==='init'){
  for(let i=0;i<args.length;i+=2){
   const key=args[i],value=args[i+1]
   if(!['--name','--capability','--template'].includes(key)||!value||value.startsWith('--'))throw Error('用法：muse init --name <名称> --capability <关键词或合同URI> [重复选择]')
   options.set(key,[...(options.get(key)??[]),value])
  }
  if((options.get('--name')?.length??0)>1)throw Error('--name 只能指定一次')
 }else if((command==='install'&&args.length!==1)||(!['search','install'].includes(command)&&args.length))throw Error('命令参数无效；运行 muse --help')
 const endpoint=environment.MCP_HOST_URL,token=environment.MCP_HOST_TOKEN
 if(!endpoint||!token)throw Error('请从 OpenMuse 选定 Workspace 的新终端运行；缺少短期 MCP 会话。')
 const client=new Client({name:'OpenMuse DevKit CLI',version:'0.3.3'})
 const transport=new StreamableHTTPClientTransport(new URL(endpoint),{requestInit:{headers:{Authorization:'Bearer '+token}}})
 await client.connect(transport)
 async function call(name:string,arguments_:any={}){
  const r=await client.callTool({name,arguments:arguments_},{timeout:['development_open_bundle','registry_install'].includes(name)?600000:120000})
  if(r.isError)throw Error(r.content.filter(c=>c.type==='text').map((c:any)=>c.text).join('\n'))
  return r.structuredContent as any
 }
 try {
  if(command==='search'){
   const query=args.filter(a=>!a.startsWith('--')).join(' ')
   const result=await call('registry_search',{query}),available=(await call('capabilities_list')).providers
   const capabilities=available.flatMap((provider:any)=>provider.contracts.filter((contract:any)=>JSON.stringify([provider.id,contract.id,contract.title,contract.mediaType]).toLowerCase().includes(query.toLowerCase())).map((contract:any)=>({provider:provider.id,version:provider.version,sha256:provider.sha256,contract:contract.id,title:contract.title,operations:contract.operations})))
   console.log(JSON.stringify({...result,capabilities},null,2));return 0
  }
  if(command==='install'){
   if(!args[0])throw Error('缺少插件ID')
   console.log(JSON.stringify(await call('registry_install',{name:args[0]}),null,2));return 0
  }
  const context=await call('workspace_describe'),cwd=await fs.realpath(process.cwd())
  const roots=await Promise.all(context.roots.map((root:any)=>fs.realpath(fileURLToPath(root.uri))))
  if(!roots.some((root:string)=>{const relative=path.relative(root,cwd);return relative===''||(!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative))}))throw Error('当前目录超出此终端授权的 Workspace；请在目标 Workspace 新开终端。')
  const assets=fileURLToPath(new URL('./template/',import.meta.url))
  let name=options.get('--name')?.[0]??path.basename(cwd).toLowerCase().replace(/[^a-z0-9-]/g,'-')
  const core=new DevkitCore(cwd,assets,environment.MCP_PUBLISHER_NAMESPACE||'io.openmuse',true)
  if(command==='init'){
   const queries=options.get('--capability')??[]
   const available=(await call('capabilities_list')).providers
   if(!queries.length)throw Error('先运行 muse search，再用一个或多个 --capability 选择依赖能力。')
   const dependencies=[]
   for(const query of queries){
    const matches=available.flatMap((provider:any)=>provider.contracts.filter((contract:any)=>contract.operations?.readSnapshot&&JSON.stringify([provider.id,contract.id,contract.title,contract.mediaType]).toLowerCase().includes(query.toLowerCase())).map((contract:any)=>({provider,contract})))
    if(matches.length!==1){console.log(JSON.stringify(matches.length?{candidates:matches.map(({provider,contract}:any)=>({provider:provider.id,version:provider.version,title:contract.title,contract:contract.id,select:['--capability',contract.id]}))}:await call('registry_search',{query}),null,2));throw Error(matches.length?'有多个候选，请使用上面列出的完整合同 URI 精确选择。':'未安装匹配能力。先 muse install <插件ID>，再初始化。')}
    const {provider,contract}=matches[0]
    if(dependencies.some(d=>d.provider.id===provider.id&&d.contract.id===contract.id))throw Error('重复的能力依赖：'+contract.id)
    dependencies.push({alias:'capability-'+(dependencies.length+1),provider:{id:provider.id,version:provider.version,sha256:provider.sha256},contract})
   }
   const result=await core.initialize(name,dependencies,await call('host_describe'),options.get('--template')?.[0])
   const ignore=path.join(cwd,'.gitignore')
   const ignoreStat=await fs.lstat(ignore).catch((e:any)=>{if(e.code!=='ENOENT')throw e;return null})
   if(ignoreStat?.isSymbolicLink())throw Error('SYMLINK_DENIED: .gitignore')
   const existing=ignoreStat?await fs.readFile(ignore,'utf8'):''
   const missing=['.devkit/','dist/','test-report.json','submission.json'].filter(value=>!existing.split(/\r?\n/).includes(value))
   if(missing.length)await fs.appendFile(ignore,'\n# DevKit local state and build output\n'+missing.join('\n')+'\n',{mode:0o600})
   console.log(JSON.stringify({...result,workspace:cwd,next:['在当前 Workspace 使用编辑器或 Agent 修改 main.js','muse check','muse dev','muse report','muse submit']},null,2));return 0
  }
  name=JSON.parse(await fs.readFile(path.join(cwd,'devkit.project.json'),'utf8')).id
  if(command==='check'){console.log(JSON.stringify(await core.validate(name),null,2));return 0}
  if(command==='dev'){
   const p=await core.pack(name),run=await call('development_open_bundle',{content:p.bytes.toString('base64'),sha256:p.sha256})
   await localDirectory(cwd,'.devkit');await safeStateWrite(path.join(cwd,'.devkit/run.json'),JSON.stringify(run))
   console.log(JSON.stringify(run,null,2));return 0
  }
  if(command==='report'){
   await localDirectory(cwd,'.devkit');const runFile=path.join(cwd,'.devkit/run.json');await regularFile(runFile);const run=JSON.parse(await fs.readFile(runFile,'utf8'))
   if(run.sha256!==(await core.pack(name)).sha256)throw Error('TEST_RUN_STALE: run muse dev again before collecting this report')
   const resource=await call('development_read_resource',{runRef:run.runRef,uri:'devkit://run/report'})
   const report=JSON.parse(resource.contents.find((c:any)=>typeof c.text==='string').text)
   console.log(JSON.stringify(await core.record(name,report),null,2));return 0
  }
  if(command==='pack'){
   const p=await core.pack(name),directory=await localDirectory(cwd,'dist')
   const file=path.join(directory,name+'-'+p.project.version+'.mcpb')
   await fs.writeFile(file,p.bytes,{flag:'wx'}).catch(async(e:any)=>{if(e.code!=='EEXIST')throw e;await regularFile(file);if(!(await fs.readFile(file)).equals(p.bytes))throw Error('VERSION_ARTIFACT_ALREADY_EXISTS_WITH_DIFFERENT_BYTES')})
   console.log(JSON.stringify({file,sha256:p.sha256},null,2));return 0
  }
  if(command==='submit'){
   let credential=environment.MARKET_DEVELOPER_TOKEN
   if(!credential){
    if(!process.stdin.isTTY)throw Error('DEVELOPER_CREDENTIAL_REQUIRED: configure MARKET_DEVELOPER_TOKEN in this process only')
    process.stderr.write('Developer token (hidden): ');process.stdin.setRawMode(true)
    credential=await new Promise<string>(resolve=>{let value='';const input=(data:Buffer)=>{for(const char of data.toString()){if(char==='\r'||char==='\n'){process.stdin.off('data',input);process.stdin.setRawMode(false);process.stdin.pause();process.stderr.write('\n');resolve(value);return}if(char==='\u0003'){process.exit(130)}if(char==='\u007f')value=value.slice(0,-1);else value+=char}};process.stdin.on('data',input);process.stdin.resume()})
   }
   console.log(JSON.stringify(await core.submit(name,environment.MCP_REGISTRY_URL||'https://plugins.openmuseai.com',credential),null,2));return 0
  }
  throw Error('未知 DevKit 命令；运行 muse --help')
 }finally{await transport.close()}
}
if(process.argv[1]?.endsWith('/cli.mjs')||process.argv[1]?.endsWith('/muse'))runCli().then(code=>{process.exitCode=code}).catch(error=>{console.error('DevKit: '+error.message);process.exitCode=1})
