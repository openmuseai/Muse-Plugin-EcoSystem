import {readFile} from 'node:fs/promises'
import {McpServer} from '@modelcontextprotocol/server'
import {serveStdio} from '@modelcontextprotocol/server/stdio'
import {z} from 'zod'
export function buildServer(){
 const server=new McpServer({name:'io.openmuse/document-explainer',version:'0.1.1'},{capabilities:{tools:{},resources:{}}})
 const ui='ui://document-explainer/toolbar',mimeType='text/html;profile=mcp-app'
 server.registerResource('Document narration toolbar',ui,{mimeType},async()=>({contents:[{uri:ui,mimeType,text:await readFile(new URL('./web/index.html',import.meta.url),'utf8')}]}))
 const uri='capability://document-explainer/resource-extensions'
 server.registerResource('Resource extensions v1',uri,{mimeType:'application/vnd.openmuse.resource-extensions+json'},async()=>({contents:[{uri,mimeType:'application/vnd.openmuse.resource-extensions+json',text:JSON.stringify({profile:'openmuse-resource-extensions/1',extensions:[{id:'narration',tool:'explainer_toolbar',mediaTypes:['application/vnd.openxmlformats-officedocument.presentationml.presentation','application/pdf'],width:360,height:152,resourceTools:['pptx_get_state','pptx_read_page','pptx_go_to_slide','pdf_get_state','pdf_read_page','pdf_go_to_page']}]})}]}))
 server.registerTool('explainer_toolbar',{description:'Show narration controls for the user-opened resource.',inputSchema:z.object({}),_meta:{ui:{resourceUri:ui}}},async()=>({content:[]}))
 return server
}
if(process.argv[1]?.endsWith('/server.mjs'))serveStdio(buildServer)
