import {App} from '@modelcontextprotocol/ext-apps'
const app=new App({name:'Easel setup',version:'0.5.0'})
const $=(id:string)=>document.getElementById(id)!
async function call(name:string,args:Record<string,unknown>={}){
  const result=await app.callServerTool({name,arguments:args},{timeout:120000})
  if(result.isError)throw Error(result.content.filter(c=>c.type==='text').map(c=>(c as any).text).join('\n'))
  return result.structuredContent??JSON.parse(result.content.filter(c=>c.type==='text').map(c=>(c as any).text).join('\n'))
}
function render(state:any){
  const rows=[['Python 3.11–3.14',state.python],['FFmpeg',state.ffmpeg],['ffprobe',state.ffprobe],['插件运行环境',state.ready?'已就绪':'待安装']]
  $('checks').replaceChildren(...rows.map(([label,value])=>{const row=document.createElement('div');row.className='step';const dot=document.createElement('span');dot.textContent=value?'✓':'!';const text=document.createElement('span');text.textContent=`${label}：${value||'未找到'}`;text.className=value?'ok':'bad';row.append(dot,text);return row}))
  $('data').textContent=`Easel 数据目录：${state.dataRoot}`;
  ($('brew') as HTMLInputElement).disabled=!state.canInstallFfmpegWithBrew
  $('start').textContent=state.ready?'修复或重新安装依赖':'开始安装'
}
async function refresh(){const state:any=await call('easel_setup_status');render(state);if(state.currentJob)await poll(state.currentJob)}
async function poll(id:string){
  const job:any=await call('easel_setup_job',{jobId:id})
  $('state').textContent=job.stage==='running'?'安装中…':job.stage==='complete'?'安装完成':'安装失败；可修正后重试'
  $('log').textContent=job.log||'等待下载…'
  render(job.status)
  if(job.stage==='running')setTimeout(()=>void poll(id).catch(showError),1300)
  else ($('start') as HTMLButtonElement).disabled=false
}
function showError(error:unknown){$('state').textContent=String(error);($('start') as HTMLButtonElement).disabled=false}
;($('refresh') as HTMLButtonElement).onclick=()=>void refresh().catch(showError)
;($('start') as HTMLButtonElement).onclick=async()=>{
  ($('start') as HTMLButtonElement).disabled=true
  $('state').textContent='正在启动安装…'
  try{
    const response:any=await call('easel_setup_start',{
      python:($('python') as HTMLInputElement).value.trim()||undefined,
      ffmpegDirectory:($('ffmpeg') as HTMLInputElement).value.trim()||undefined,
      installFfmpeg:($('brew') as HTMLInputElement).checked,
    })
    void poll(response.jobId).catch(showError)
  }catch(error){showError(error)}
}
void app.connect().then(refresh).catch(showError)
