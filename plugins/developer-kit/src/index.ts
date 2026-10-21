import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { McpServer } from '@modelcontextprotocol/server'
import { serveStdio } from '@modelcontextprotocol/server/stdio'
import { z } from 'zod'
import { DevkitCore } from '../../../packages/devkit-core/src/index.js'

export function buildServer(){
 const server=new McpServer({name:'io.openmuse/developer-kit',version:'0.2.0'},{capabilities:{tools:{},resources:{}}})
 let core:DevkitCore|undefined
 const get=()=>{if(!process.env.PROJECT_DIRECTORY)throw Error('PROJECT_DIRECTORY_CONFIGURATION_REQUIRED');return core??=new DevkitCore(process.env.PROJECT_DIRECTORY,fileURLToPath(new URL('./template/',import.meta.url)),process.env.PUBLISHER_NAMESPACE||'io.openmuse')}
 const output=z.object({}).catchall(z.unknown())
 const tool=(name:string,description:string,input:any,fn:(args:any)=>Promise<any>,extra:any={})=>server.registerTool(name,{description,inputSchema:input,outputSchema:output,...extra},async(args:any)=>{
  try{const result=await fn(args);return {content:[{type:'text' as const,text:JSON.stringify(result)}],structuredContent:result}}
  catch(error){const safe=error instanceof Error?error.message:'OPERATION_FAILED';const code=/^[A-Z0-9_]+$/.test(safe)?safe:'PROJECT_OPERATION_FAILED';return {isError:true,content:[{type:'text' as const,text:code}]}}
 })
 server.registerResource('Plugin DevKit','ui://developer-kit/main',{mimeType:'text/html;profile=mcp-app'},async()=>({contents:[{uri:'ui://developer-kit/main',mimeType:'text/html;profile=mcp-app',text:await readFile(new URL('./web/index.html',import.meta.url),'utf8')}]}))
 tool('devkit_open','Open the in-app Plugin DevKit.',z.object({}),async()=>({ready:true}),{_meta:{ui:{resourceUri:'ui://developer-kit/main'}}})
 tool('devkit_list_projects','List projects inside the user-authorized project directory.',z.object({}),async()=>get().list())
 tool('devkit_initialize_project','Initialize an independent project with multiple exact public capability dependencies and Host build.',z.object({project:z.string(),dependencies:z.array(z.any()).min(1).max(8),host:z.any()}),async a=>get().initialize(a.project,a.dependencies,a.host))
 tool('devkit_read_file','Read a project file. Generated dependency files are read-only.',z.object({project:z.string(),file:z.string()}),async a=>get().read(a.project,a.file))
 tool('devkit_write_file','Save a project file only if its expected SHA matches; no arbitrary filesystem paths.',z.object({project:z.string(),file:z.string(),text:z.string(),expectedSha256:z.string()}),async a=>get().write(a.project,a.file,a.text,a.expectedSha256))
 tool('devkit_validate','Check JavaScript syntax and required run export. Does not execute source on the backend.',z.object({project:z.string()}),async a=>get().validate(a.project))
 tool('devkit_pack','Build a deterministic standard MCPB using a fixed offline runtime. No shell or source checkout.',z.object({project:z.string()}),async a=>{const p=await get().pack(a.project);return {content:p.bytes.toString('base64'),sha256:p.sha256,codeSha256:p.codeSha256}})
 tool('devkit_record_test','Validate a real development-client report against the exact code and locked providers. This is not server attestation.',z.object({project:z.string(),report:z.any()}),async a=>get().record(a.project,a.report))
 tool('devkit_submit','Upload the tested immutable package and create a pending review submission. Never approve.',z.object({project:z.string()}),async a=>get().submit(a.project,process.env.MARKET_ORIGIN||'https://plugins.openmuseai.com',process.env.DEVELOPER_TOKEN||''))
 return server
}
if(process.argv[1]?.endsWith('/server.mjs'))serveStdio(buildServer)
