import { CapabilityClient, type Provider, type Contract } from '../../../packages/plugin-sdk/src/index.js'
import { EditorView, basicSetup } from 'codemirror'
import { Compartment } from '@codemirror/state'
import { javascript } from '@codemirror/lang-javascript'
const editable=new Compartment()
const client=new CapabilityClient(),$=(id:string)=>document.getElementById(id)!
let editor:EditorView,providers:Provider[]=[],selected=new Map<string,{provider:Provider,contract:Contract}>(),project='',file='main.js',revision='',runRef='',testPassed=false,dirty=false
const status=(text:string)=>{$('status').textContent=text;$('status').setAttribute('role','status')}
const buttons=()=>{for(const id of ['save','validate','debug','report','submit'])($ (id) as HTMLButtonElement).disabled=!project||id==='submit'&&!testPassed}
async function action(task:()=>Promise<void>){try{await task()}catch(error){status(String(error))}finally{buttons()}}
async function ask(message:string,yes:string){
 const dialog=document.createElement('dialog'),text=document.createElement('p'),cancel=document.createElement('button'),accept=document.createElement('button')
 text.textContent=message;cancel.textContent='取消';accept.textContent=yes;accept.className='primary'
 dialog.append(text,cancel,accept);document.body.append(dialog)
 return new Promise<boolean>(resolve=>{cancel.onclick=()=>dialog.close('no');accept.onclick=()=>dialog.close('yes');dialog.onclose=()=>{const result=dialog.returnValue==='yes';dialog.remove();resolve(result)};dialog.showModal()})
}
async function load(name='main.js'){
 if(dirty&&!await ask('当前文件未保存，仍然切换？','放弃未保存更改'))return
 file=name;const data=await client.call('devkit_read_file',{project,file});revision=data.sha256
 editor.dispatch({changes:{from:0,to:editor.state.doc.length,insert:data.text}});dirty=false
 editor.contentDOM.setAttribute('aria-label','插件源代码')
 editor.dispatch({effects:editable.reconfigure(EditorView.editable.of(file==='main.js'||file==='README.md'))})
}
// Editor remains usable offline. CodeMirror owns source editing; the backend only validates/assembles.
async function boot(){
 editor=new EditorView({doc:'// 先选择能力并初始化项目。',extensions:[basicSetup,javascript(),editable.of(EditorView.editable.of(true)),EditorView.updateListener.of(u=>{if(u.docChanged){dirty=true;testPassed=false;buttons()}})],parent:$('editor')})
 await client.connect();const host=await client.call('host_describe');$('host').textContent='Desktop '+host.implementation.version+' · '+host.implementation.buildSha256.slice(0,12)
 providers=await client.providers();$('capabilities').replaceChildren()
 for(const provider of providers)for(const contract of provider.contracts){
  if(!contract.operations?.readSnapshot)continue
  const key=provider.id+'@'+contract.id,label=document.createElement('label'),checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.setAttribute('aria-label',contract.title)
  const text=document.createElement('span');text.textContent=contract.title+' · '+provider.version
  checkbox.onchange=()=>{if(checkbox.checked)selected.set(key,{provider,contract});else selected.delete(key);$('selection').textContent='已选择 '+selected.size+' 项能力（可多选）'};label.append(checkbox,text);$('capabilities').append(label)
 }
 if(!providers.length)status('未发现公开能力。请先从市场安装 Provider。');else status('环境已就绪。选择 PPTX 和 PDF 能力后初始化。')
 const projects=await client.call('devkit_list_projects');const picker=$('projects') as HTMLSelectElement
 for(const id of projects.projects){const option=new Option(id,id);picker.add(option)}
 picker.onchange=()=>void action(async()=>{if(!picker.value)return;project=picker.value;await load();$('project-title').textContent=project;status('已恢复项目；重新真实调试后才能提交。')})
 $('initialize').onclick=()=>void action(async()=>{
  const id=($('name') as HTMLInputElement).value.trim();if(!selected.size)throw Error('请至少选择一项能力')
  const dependencies=Array.from(selected.values()).map(({provider,contract},i)=>({alias:'capability-'+(i+1),provider:{id:provider.id,version:provider.version,sha256:provider.sha256},contract}))
  await client.call('devkit_initialize_project',{project:id,dependencies,host});project=id;await load();$('project-title').textContent=id
  picker.add(new Option(id,id));picker.value=id;status('项目已初始化；合同、Provider 和 Host 构建已锁定。')
 })
 for(const button of Array.from(document.querySelectorAll<HTMLButtonElement>('[data-file]')))button.onclick=()=>void action(()=>load(button.dataset.file!))
 $('save').onclick=()=>void action(async()=>{const r=await client.call('devkit_write_file',{project,file,text:editor.state.doc.toString(),expectedSha256:revision});revision=r.sha256;dirty=false;testPassed=false;status('已保存 · '+revision.slice(0,12))})
 $('validate').onclick=()=>void action(async()=>{if(dirty)throw Error('请先保存源码');await client.call('devkit_validate',{project});status('语法检查通过；尚未完成真实 Provider 调试。')})
 $('debug').onclick=()=>void action(async()=>{if(dirty)throw Error('请先保存源码');status('正在打包并打开独立开发预览…');const artifact=await client.call('devkit_pack',{project});const run=await client.call('development_open_bundle',{content:artifact.content,sha256:artifact.sha256});runRef=run.runRef;status('开发预览已打开。选择两份真实资料并运行，关闭预览后读取报告。')})
 $('report').onclick=()=>void action(async()=>{if(!runRef)throw Error('请先启动调试');const resource=await client.call('development_read_resource',{runRef,uri:'devkit://run/report'});const text=resource.contents.find((c:any)=>typeof c.text==='string')?.text;const report=JSON.parse(text);await client.call('devkit_record_test',{project,report});testPassed=true;status('真实调试报告已匹配当前代码与全部 Provider。可以提交审核。')})
 $('submit').onclick=()=>void action(async()=>{if(dirty||!testPassed)throw Error('请完成真实调试');if(!await ask('提交当前版本到市场审核？待审版本不会自动上架。','确认提交审核'))return;status('正在上传并提交审核…');const r=await client.call('devkit_submit',{project});$('receipt').textContent=JSON.stringify(r,null,2);status('已提交 · 待审核 · '+r.submissionId)})
 buttons()
}
void boot().catch(error=>status('启动失败：'+String(error)))
