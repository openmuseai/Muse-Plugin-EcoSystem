import type {NarrationServices} from './narrator.js'
/** Business clients for public provider APIs; Host never interprets these names. */
export function providerServices(call:(name:string,args?:any)=>Promise<any>,uri:string,mediaType:string):NarrationServices {
 const pdf=mediaType==='application/pdf'
 const stateTool=pdf?'pdf_get_state':'pptx_get_state',readTool=pdf?'pdf_read_page':'pptx_read_page',navigateTool=pdf?'pdf_go_to_page':'pptx_go_to_slide',indexKey=pdf?'pageIndex':'slideIndex'
 let agent:string|undefined
 async function resource(name:string,args:any={}){return call('call_resource_tool',{uri,name,arguments:args})}
 async function getAgent(){
  if(agent)return agent
  const {plugins}=await call('list_plugin_tools')
  const matches=plugins.filter((p:any)=>['dsh_generate','dsh_generation_status','dsh_generation_cancel'].every(n=>p.tools.some((t:any)=>t.name===n)))
  if(matches.length!==1)throw Error('请启用一个兼容的 DSH Agent 插件后重试')
  agent=matches[0].id;return agent
 }
 const agentCall=async(name:string,args:any)=>call('call_plugin_tool',{plugin:await getAgent(),name,arguments:args})
 return {
  async state(){
   const tools=await call('list_resource_tools',{uri})
   if(![stateTool,readTool,navigateTool].every(n=>tools.tools.some((t:any)=>t.name===n)))throw Error('编辑器尚未支持实时讲解，请更新对应插件后重新打开文档')
   const s=await resource(stateTool);return {name:s.name,pageCount:s.pageCount,index:s[indexKey]}
  },
  async goTo(index){await resource(navigateTool,{[indexKey]:index})},
  async read(index){return resource(readTool,{[indexKey]:index})},
  generate:(text,conversationRef)=>agentCall('dsh_generate',{text,...(conversationRef?{conversationRef}:{})}),
  status:taskRef=>agentCall('dsh_generation_status',{taskRef}),
  cancel:async taskRef=>{const result=await agentCall('dsh_generation_cancel',{taskRef});if(!['cancelled','completed'].includes(result.status))throw Error('GENERATION_CANCEL_UNCONFIRMED')},
  delay:ms=>new Promise(resolve=>setTimeout(resolve,ms)),
 }
}
