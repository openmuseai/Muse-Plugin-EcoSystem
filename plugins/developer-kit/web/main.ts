import {CapabilityClient} from '../../../packages/plugin-sdk/src/index.js'
const client=new CapabilityClient(),$=(id:string)=>document.getElementById(id)!
async function load(){
 await client.connect()
 const host=await client.call('host_describe'),workspace=await client.call('workspace_describe')
 $('host').textContent='Desktop '+host.implementation.version+' · '+host.implementation.buildSha256.slice(0,12)
 $('workspace').textContent=workspace.roots.map((r:any)=>r.name+' · '+decodeURI(r.uri)).join('\n')
 $('status').textContent='请在这个 Workspace 的终端使用 muse CLI。工程文件归当前 Workspace 管理。'
 const search=async()=>{
  $('results').textContent='正在搜索已安装插件和在线市场…'
  const results=await client.call('registry_search',{query:($('query') as HTMLInputElement).value})
  $('results').replaceChildren()
  for(const p of results.plugins){const row=document.createElement('div');row.className='plugin';const title=document.createElement('strong'),detail=document.createElement('p'),command=document.createElement('code');title.textContent=p.title+' '+p.version+(p.installed?' · 已安装':' · 在线市场');detail.textContent=p.description;command.textContent=p.installed?'muse init --name my-plugin --capability '+p.name:'muse install '+p.name;row.append(title,detail,command);$('results').append(row)}
 }
 $('search').onclick=()=>void search().catch(error=>{$('status').textContent=String(error)})
 await search()
}
void load().catch(error=>{$('status').textContent='请更新 Desktop 的 Workspace MCP 支持：'+String(error)})
