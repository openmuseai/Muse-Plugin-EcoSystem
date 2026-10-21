// Independent MCP Apps host verifies the shipped PDF UI and live tools.
import {readFile,mkdir,writeFile} from 'node:fs/promises'
import {createServer} from 'node:http'
import assert from 'node:assert/strict'
import {chromium} from 'playwright-core'
const ui=await readFile('plugins/pdf-reader/dist/web/index.html','utf8'),bytes=await readFile('plugins/pdf-reader/fixtures/quarterly-brief.pdf')
const html=`<!doctype html><style>html,body,iframe{margin:0;width:100%;height:100%;border:0}</style><iframe id="view" sandbox="allow-scripts"></iframe><script>
const view=document.querySelector('iframe'),pending=new Map();let id=0;
window.callTool=(name,args={})=>new Promise((resolve,reject)=>{const key=++id;pending.set(key,{resolve,reject});view.contentWindow.postMessage({jsonrpc:'2.0',id:key,method:'tools/call',params:{name,arguments:args}},'*')});
addEventListener('message',event=>{if(event.source!==view.contentWindow)return;const m=event.data,reply=result=>view.contentWindow.postMessage({jsonrpc:'2.0',id:m.id,result},'*');
if(!m.method&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);return;}
if(m.method==='ui/initialize')reply({protocolVersion:'2026-01-26',hostInfo:{name:'Independent PDF test',version:'1.0.0'},hostCapabilities:{updateModelContext:{text:{}}},hostContext:{theme:'light',platform:'desktop',displayMode:'inline'}});
if(m.method==='ui/notifications/initialized')view.contentWindow.postMessage({jsonrpc:'2.0',method:'ui/notifications/tool-input',params:{arguments:{name:'quarterly-brief.pdf',content:'${bytes.toString('base64')}'}}},'*');
if(m.method==='ui/update-model-context')reply({});});view.srcdoc=new TextDecoder().decode(Uint8Array.from(atob('${Buffer.from(ui).toString('base64')}'),c=>c.charCodeAt(0)));
</script>`
const server=createServer((_,res)=>res.end(html));await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve))
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true})
try{
 const page=await browser.newPage({viewport:{width:900,height:760}}),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:'+server.address().port)
 const view=page.frameLocator('#view');await view.locator('html[data-pdf-ready="2"]').waitFor({timeout:30000})
 const call=async(name,args={})=>{const result=await page.evaluate(({name,args})=>window.callTool(name,args),{name,args});assert(!result.isError,JSON.stringify(result));return JSON.parse(result.content[0].text)}
 assert.equal((await call('pdf_get_state')).pageIndex,0)
 const first=await call('pdf_read_page',{pageIndex:0});assert(first.text.length>20)
 await call('pdf_go_to_page',{pageIndex:1});assert.equal((await call('pdf_get_state')).pageIndex,1)
 assert((await call('pdf_read_page',{pageIndex:1})).text.length>20)
 assert.deepEqual(errors,[])
 await mkdir('dist/document-explainer-verification',{recursive:true});await page.screenshot({path:'dist/document-explainer-verification/pdf-view.png'})
 await writeFile('dist/document-explainer-verification/pdf-view.json',JSON.stringify({pages:2,rendered:true,liveRead:true,navigation:true,errors},null,2))
 console.log('PDF.js render + live text + page navigation passed')
}finally{await browser.close();server.close()}
