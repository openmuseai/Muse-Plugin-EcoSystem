import { spawn, spawnSync } from 'node:child_process'
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir, platform } from 'node:os'
import { delimiter, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const bundleRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
// Development smoke tests may redirect the state; the released Host supplies
// no inherited environment, so ordinary installs use the stable default.
export const dataRoot = process.env.EASEL_DATA_ROOT || join(homedir(), '.openmuse', 'easel')
const extraPaths = platform() === 'darwin' ? ['/opt/homebrew/bin', '/usr/local/bin'] : []
const binaryPath = [process.env.PATH || '', ...extraPaths].join(delimiter)
const jobFile=join(dataRoot,'runtime','setup-job.json')
const logFile=join(dataRoot,'runtime','setup.log')
type Job={jobId:string,stage:'running'|'complete'|'failed',pid?:number,exitCode?:number}
function readJob():Job|null {
  try {return JSON.parse(readFileSync(jobFile,'utf8')) as Job} catch{return null}
}
function writeJob(job:Job){writeFileSync(jobFile,JSON.stringify(job))}
function alive(pid?:number):boolean {
  if(!pid)return false
  try{process.kill(pid,0);return true}catch{return false}
}

function command(executable: string, args: string[]) {
  return spawnSync(executable, args, { encoding:'utf8', timeout:8000, env:{...process.env, PATH:binaryPath} })
}
export function findBinary(name:string, provided?:string):string | null {
  if (provided) {
    const path=resolve(provided)
    return existsSync(path) ? path : null
  }
  for(const dir of binaryPath.split(delimiter)){
    if(!dir)continue
    const path=join(dir,platform()==='win32'?`${name}.exe`:name)
    if(existsSync(path))return path
  }
  return null
}
export function findPython(provided?:string):string | null {
  if(provided){
    const candidate=findBinary('python',provided)
    if(candidate && pythonSupported(candidate))return candidate
    return null
  }
  const candidates=[join(homedir(),'.local/bin/python3.12'),...extraPaths.flatMap(dir=>[join(dir,'python3.13'),join(dir,'python3.12'),join(dir,'python3.11')]),'/usr/bin/python3']
  return candidates.find(path=>existsSync(path)&&pythonSupported(path))||null
}
function pythonSupported(path:string):boolean {
  const result=command(path,['-c','import sys; print(sys.version_info.major,sys.version_info.minor)'])
  if(result.status!==0)return false
  const [major,minor]=result.stdout.trim().split(' ').map(Number)
  return major===3 && minor>=11 && minor<=14
}
export function status() {
  const python=join(dataRoot,'runtime','venv',platform()==='win32'?'Scripts/python.exe':'bin/python')
  const receipt=join(dataRoot,'runtime','install-status.json')
  const installed=existsSync(receipt) ? JSON.parse(readFileSync(receipt,'utf8')) : null
  const ffmpeg=findBinary('ffmpeg',installed?.ffmpeg)
  const ffprobe=findBinary('ffprobe',installed?.ffprobe)
  let pythonReady=false
  if(installed?.ready && existsSync(python) && existsSync(installed.browsers)){
    const probe=spawnSync(python,['-c','import PIL, playwright; from playwright.sync_api import sync_playwright; p=sync_playwright().start(); print(p.chromium.executable_path); p.stop()'],{
      encoding:'utf8',timeout:5000,env:{...process.env,PLAYWRIGHT_BROWSERS_PATH:installed.browsers},
    })
    pythonReady=probe.status===0&&existsSync(probe.stdout.trim())
  }
  const ready=Boolean(installed?.ready && pythonReady && ffmpeg && ffprobe)
  return {ready, python:findPython(), ffmpeg, ffprobe, dataRoot, installed, currentJob:readJob()?.jobId, platform:platform(), canInstallFfmpegWithBrew:platform()==='darwin'&&Boolean(findBinary('brew'))}
}
export function startSetup({python,ffmpegDirectory,installFfmpeg}:{python?:string,ffmpegDirectory?:string,installFfmpeg:boolean}) {
  const existing=readJob()
  if(existing?.stage==='running'&&alive(existing.pid))throw Error('SETUP_ALREADY_RUNNING')
  const interpreter=findPython(python)
  if(!interpreter)throw Error('PYTHON_3_11_TO_3_14_REQUIRED')
  if(installFfmpeg && !findBinary('brew'))throw Error('HOMEBREW_REQUIRED')
  mkdirSync(join(dataRoot,'runtime'),{recursive:true})
  const id=Date.now().toString(36)
  const args=[join(bundleRoot,'runtime','install.py'),'--workspace',dataRoot,'--python',interpreter,'--job-id',id]
  if(ffmpegDirectory)args.push('--ffmpeg-directory',ffmpegDirectory)
  if(installFfmpeg)args.push('--install-ffmpeg-with-brew')
  const log=openSync(logFile,'w')
  const child=spawn(interpreter,args,{cwd:dataRoot,env:{...process.env,PATH:binaryPath},stdio:['ignore',log,log],detached:true})
  closeSync(log)
  writeJob({jobId:id,stage:'running',pid:child.pid})
  child.on('error',error=>{writeFileSync(logFile,String(error)+'\n',{flag:'a'});writeJob({jobId:id,stage:'failed',exitCode:-1})})
  child.on('exit',code=>{if(readJob()?.stage==='running')writeJob({jobId:id,stage:code===0?'complete':'failed',exitCode:code??-1})})
  child.unref()
  return {jobId:id,stage:'running'}
}
export function setupJob(id:string) {
  let job=readJob()
  if(!job||job.jobId!==id)throw Error('UNKNOWN_SETUP_JOB')
  if(job.stage==='running'&&!alive(job.pid)){
    job={jobId:id,stage:'failed',exitCode:-1};writeJob(job)
  }
  let log=''
  try{log=readFileSync(logFile,'utf8').slice(-12000)}catch{}
  return {...job,log,status:status()}
}
export function runtimeEnv() {
  const state=status()
  if(!state.ready)throw Error('EASEL_SETUP_REQUIRED')
  const python=join(dataRoot,'runtime','venv',platform()==='win32'?'Scripts/python.exe':'bin/python')
  return {python,env:{...process.env,PATH:[dirname(state.ffmpeg!),binaryPath].join(delimiter),PLAYWRIGHT_BROWSERS_PATH:join(dataRoot,'runtime','browsers'),EASEL_DATA_ROOT:dataRoot}}
}
