import { readFile, writeFile } from 'node:fs/promises'
import {readFileSync} from 'node:fs'
const metadata=JSON.parse(readFileSync(new URL('./manifest.json',import.meta.url),'utf8'))
import { McpServer } from '@modelcontextprotocol/server'
import { serveStdio } from '@modelcontextprotocol/server/stdio'
import { z } from 'zod'
serveStdio(()=>{
 const server=new McpServer({name:metadata.name,version:metadata.version},{capabilities:{tools:{},resources:{}}})
 server.registerResource('Plugin UI','ui://independent-plugin/main',{mimeType:'text/html;profile=mcp-app'},async()=>({contents:[{uri:'ui://independent-plugin/main',mimeType:'text/html;profile=mcp-app',text:await readFile(new URL('./index.html',import.meta.url),'utf8')}]}))
 const project=JSON.parse(awaitableProject())
 function awaitableProject(){return readFileSync(new URL('./devkit/project.json',import.meta.url),'utf8')}
 if(project.template==='document-explainer'){
  const uri='capability://independent-plugin/resource-extensions'
  server.registerResource('Resource extensions v1',uri,{mimeType:'application/vnd.openmuse.resource-extensions+json'},async()=>({contents:[{uri,mimeType:'application/vnd.openmuse.resource-extensions+json',text:JSON.stringify({profile:'openmuse-resource-extensions/1',extensions:[{id:'narration',tool:'open_plugin',mediaTypes:JSON.parse(readFileSync(new URL('./source/devkit.lock.json',import.meta.url),'utf8')).dependencies.map((d:any)=>d.contract.mediaType),width:360,height:152,resourceTools:['pptx_get_state','pptx_read_page','pptx_go_to_slide','pdf_get_state','pdf_read_page','pdf_go_to_page']}]})}]}))
 }
 server.registerResource('Development report','devkit://run/report',{mimeType:'application/json'},async()=>({contents:[{uri:'devkit://run/report',mimeType:'application/json',text:await readFile(new URL('./run-report.json',import.meta.url),'utf8').catch(()=>'{"status":"not-run"}') }]}))
 server.registerTool('open_plugin',{inputSchema:z.object({}),outputSchema:z.object({ready:z.boolean()}),_meta:{ui:{resourceUri:'ui://independent-plugin/main'}}},async()=>({content:[],structuredContent:{ready:true}}))
 server.registerTool('record_run',{inputSchema:z.object({report:z.object({status:z.literal('passed'),codeSha256:z.string().regex(/^[a-f0-9]{64}$/),providers:z.array(z.object({id:z.string(),version:z.string(),sha256:z.string(),pageCount:z.number().int().positive(),source:z.string()})).min(1),completedAt:z.string()})}),outputSchema:z.object({recorded:z.boolean()}),_meta:{ui:{visibility:['app']}}},async({report})=>{const previous=JSON.parse(await readFile(new URL('./run-report.json',import.meta.url),'utf8').catch(()=>'{}'))
 const expected=JSON.parse(readFileSync(new URL('./source/devkit.lock.json',import.meta.url),'utf8')).dependencies
 const providers=[...(previous.codeSha256===report.codeSha256?previous.providers??[]:[])]
 for(const p of report.providers){
  if(!expected.some((d:any)=>d.provider.id===p.id&&d.provider.sha256===p.sha256&&d.provider.version===p.version))throw Error('UNLOCKED_PROVIDER_REPORT')
  const index=providers.findIndex((v:any)=>v.id===p.id);if(index<0)providers.push(p);else providers[index]=p
 }
 const merged={...report,providers,status:expected.every((d:any)=>providers.some((p:any)=>p.id===d.provider.id&&p.sha256===d.provider.sha256))?'passed':'partial'}
 await writeFile(new URL('./run-report.json',import.meta.url),JSON.stringify(merged));return {content:[],structuredContent:{recorded:true}}})
 return server
})
