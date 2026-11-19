import {readFile} from 'node:fs/promises';
import {McpServer} from '@modelcontextprotocol/server';
import {serveStdio} from '@modelcontextprotocol/server/stdio';
import {Client,StreamableHTTPClientTransport} from '@modelcontextprotocol/client';
import {toolsSchemas} from '../../../../Muse-CI/packages/contracts/index.ts';
/* Desktop stdio adapter. CI business remains in the bound execution backend. */
const endpoint=new URL(process.env.CI_BACKEND_URL?.trim()||'http://127.0.0.1:4180/mcp');
if(endpoint.protocol!=='https:'&&!(endpoint.protocol==='http:'&&['127.0.0.1','localhost','[::1]'].includes(endpoint.hostname)))throw Error('TRUSTED_BACKEND_REQUIRED');
const token=process.env.CI_MCP_TOKEN;
let client:Client|undefined;
async function remote(){if(!token)throw Error('BACKEND_AUTH_CONFIGURATION_REQUIRED');if(!client){const c=new Client({name:'Muse-CI Desktop plugin',version:'0.2.0'});await c.connect(new StreamableHTTPClientTransport(endpoint,{requestInit:{headers:{authorization:'Bearer '+token}},fetch:(url,init)=>fetch(url,{...init,redirect:'error'})}));client=c;}return client;}
await serveStdio(()=>{const server=new McpServer({name:'io.openmuse.ci',version:'0.2.0'},{capabilities:{tools:{},resources:{}}});server.registerResource('Muse-CI','ui://muse-ci/main',{mimeType:'text/html;profile=mcp-app'},async()=>({contents:[{uri:'ui://muse-ci/main',mimeType:'text/html;profile=mcp-app',text:await readFile(new URL('./web/index.html',import.meta.url),'utf8')}]}));for(const [name,inputSchema] of Object.entries(toolsSchemas)){server.registerTool(name,{description:name.replaceAll('_',' '),inputSchema,...(name==='ci_open'?{_meta:{ui:{resourceUri:'ui://muse-ci/main'}}}:{})},async(args:any)=>{try{return await (await remote()).callTool({name,arguments:args}) as any;}catch{await client?.close().catch(()=>{});client=undefined;return {isError:true,content:[{type:'text' as const,text:'BACKEND_UNAVAILABLE_OR_AUTH_REQUIRED'}]};}});}return server;});
