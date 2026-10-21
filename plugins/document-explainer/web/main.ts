import {App} from '@modelcontextprotocol/ext-apps'
import {Narrator} from '../src/narrator.js'
import {providerServices} from '../src/providers.js'
export async function mountNarration(options:{onPageCompleted?:(mediaType:string,index:number,pageCount:number)=>Promise<void>}={}) {
const app=new App({name:'Document Explainer',version:'0.1.0'})
let narrator:Narrator|undefined,resourceUri=''
const start=document.querySelector<HTMLButtonElement>('#start')!,stop=document.querySelector<HTMLButtonElement>('#stop')!,mode=document.querySelector<HTMLSelectElement>('#mode')!,status=document.querySelector('#status')!,page=document.querySelector('#page')!
async function call(name:string,args:any={}){
 const result=await app.callServerTool({name,arguments:args},{timeout:120000})
 if(result.isError)throw Error(result.content.filter(c=>c.type==='text').map((c:any)=>c.text).join('\n'))
 if(result.structuredContent)return result.structuredContent
 const text=result.content.filter(c=>c.type==='text').map((c:any)=>c.text).join('\n')
 return JSON.parse(text)
}
function update(){
 if(!narrator)return
 const n=narrator
 start.textContent=n.running?'暂停':n.state==='paused'?'继续':n.state==='error'?'重试':'开始讲解'
 start.disabled=!n.active;stop.disabled=n.state==='idle';mode.disabled=n.running||n.state==='paused'
 page.textContent=n.pageCount?`第 ${Math.min(n.index+1,n.pageCount)} / ${n.pageCount} 页`:''
 status.textContent=n.message;status.setAttribute('data-state',n.state)
 document.documentElement.dataset.narrationState=n.state
}
app.ontoolinput=({arguments:args})=>{
 if(typeof args?.resourceUri!=='string'||typeof args.mediaType!=='string')return
 if(resourceUri!==args.resourceUri){
  narrator?.setActive(false);resourceUri=args.resourceUri
  narrator=new Narrator(providerServices(call,resourceUri,args.mediaType),update, (index,count)=>options.onPageCompleted?.(args.mediaType as string,index,count)??Promise.resolve())
 }
 narrator!.setActive(args.active!==false);update()
}
start.onclick=()=>{if(narrator?.running)void narrator.pause();else void narrator?.start(mode.value as 'first'|'current')}
stop.onclick=()=>{void narrator?.stop()}
await app.connect().catch(()=>{status.textContent='无法连接应用。请重新打开文档。'})
return {app,narrator}
}
