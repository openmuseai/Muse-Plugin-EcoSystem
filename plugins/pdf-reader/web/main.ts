import { App } from '@modelcontextprotocol/ext-apps'
import { getDocument } from 'pdfjs-dist/build/pdf.mjs'
import * as worker from 'pdfjs-dist/build/pdf.worker.mjs'
;(globalThis as any).pdfjsWorker=worker
const app=new App({name:'PDF Reader',version:'0.2.0'},{tools:{listChanged:false}})
let doc:any,name='',index=0,revision=0,epoch=0,pageText=''
const canvas=document.querySelector('canvas')!,status=document.querySelector('#status')!
let rendering:Promise<void>=Promise.resolve()
async function render(next:number){
 if(!doc||!Number.isInteger(next)||next<0||next>=doc.numPages)throw Error('INVALID_PAGE')
 const task=async()=>{
  index=next
  const page=await doc.getPage(index+1),viewport=page.getViewport({scale:1.3})
  canvas.width=viewport.width;canvas.height=viewport.height
  await page.render({canvas,canvasContext:canvas.getContext('2d')!,viewport}).promise
  const text=await page.getTextContent();pageText=text.items.map((i:any)=>i.str??'').join(' ')
  status.textContent=`第 ${index+1} / ${doc.numPages} 页`
  document.documentElement.dataset.pdfReady=String(doc.numPages)
  await app.updateModelContext({structuredContent:{name,pageCount:doc.numPages,pageIndex:index,revision}})
 }
 rendering=rendering.then(task,task);return rendering
}
app.ontoolinput=async({arguments:args})=>{
 try{
 const generation=++epoch
 if(typeof args?.content!=='string')return
 name=String(args.name??'Document.pdf');const bytes=Uint8Array.from(atob(args.content),c=>c.charCodeAt(0))
 const loaded=await getDocument({data:bytes,useSystemFonts:true,isEvalSupported:false,useWasm:false}).promise
 if(generation!==epoch){await loaded.destroy();return}
 await doc?.destroy();doc=loaded;revision++;await render(0)
 }catch(error){status.textContent='PDF 打开失败：'+String(error)}
}
const integer={type:'integer',minimum:0}
const tool=(name:string,properties:any={},required:string[]=[],readOnlyHint=true)=>({name,description:name+' · PDF live pages v1',inputSchema:{type:'object' as const,properties,required,additionalProperties:false},annotations:{readOnlyHint}})
const tools=[tool('pdf_get_state'),tool('pdf_read_page',{pageIndex:integer},['pageIndex']),tool('pdf_go_to_page',{pageIndex:integer},['pageIndex'],false)]
app.onlisttools=async()=>({tools})
app.oncalltool=async({name:operation,arguments:args})=>{
 try{
 if(!doc)throw Error('DOCUMENT_NOT_READY')
 await rendering
 let result:any
 if(operation==='pdf_get_state')result={name,revision,pageCount:doc.numPages,pageIndex:index}
 else if(operation==='pdf_go_to_page'){await render(Number(args?.pageIndex));result={pageIndex:index,revision}}
 else if(operation==='pdf_read_page'){
  const pageIndex=Number(args?.pageIndex)
  if(!Number.isInteger(pageIndex)||pageIndex<0||pageIndex>=doc.numPages)throw Error('INVALID_PAGE')
  const p=await doc.getPage(pageIndex+1),text=await p.getTextContent()
  result={name,revision,index:pageIndex,text:text.items.map((i:any)=>i.str??'').join(' '),status:text.items.length?'text':'no-text-layer'}
 }else throw Error('UNKNOWN_TOOL')
 return {content:[{type:'text',text:JSON.stringify(result)}]}
 }catch(error){return {isError:true,content:[{type:'text',text:String(error)}]}}
}
document.querySelector('#previous')!.addEventListener('click',()=>{void render(Math.max(0,index-1))})
document.querySelector('#next')!.addEventListener('click',()=>{void render(Math.min(doc.numPages-1,index+1))})
void app.connect()
