import { readFile, writeFile } from 'node:fs/promises'
import {readFileSync} from 'node:fs'
const metadata=JSON.parse(readFileSync(new URL('./manifest.json',import.meta.url),'utf8'))
import { McpServer } from '@modelcontextprotocol/server'
import { serveStdio } from '@modelcontextprotocol/server/stdio'
import { z } from 'zod'
serveStdio(()=>{
 const server=new McpServer({name:metadata.name,version:metadata.version},{capabilities:{tools:{},resources:{}}})
 server.registerResource('Plugin UI','ui://independent-plugin/main',{mimeType:'text/html;profile=mcp-app'},async()=>({contents:[{uri:'ui://independent-plugin/main',mimeType:'text/html;profile=mcp-app',text:await readFile(new URL('./index.html',import.meta.url),'utf8')}]}))
 server.registerResource('Development report','devkit://run/report',{mimeType:'application/json'},async()=>({contents:[{uri:'devkit://run/report',mimeType:'application/json',text:await readFile(new URL('./run-report.json',import.meta.url),'utf8').catch(()=>'{"status":"not-run"}') }]}))
 server.registerTool('open_plugin',{inputSchema:z.object({}),outputSchema:z.object({ready:z.boolean()}),_meta:{ui:{resourceUri:'ui://independent-plugin/main'}}},async()=>({content:[],structuredContent:{ready:true}}))
 server.registerTool('record_run',{inputSchema:z.object({report:z.object({status:z.literal('passed'),codeSha256:z.string().regex(/^[a-f0-9]{64}$/),providers:z.array(z.object({id:z.string(),version:z.string(),sha256:z.string(),pageCount:z.number().int().positive(),source:z.string()})).min(1),completedAt:z.string()})}),outputSchema:z.object({recorded:z.boolean()}),_meta:{ui:{visibility:['app']}}},async({report})=>{await writeFile(new URL('./run-report.json',import.meta.url),JSON.stringify(report));return {content:[],structuredContent:{recorded:true}}})
 return server
})
