import { spawn } from 'node:child_process'
import { join } from 'node:path'
import { bundleRoot, runtimeEnv, status } from './setup.js'

const args=process.argv.slice(2)
if(args[0]==='status'){
  process.stdout.write(JSON.stringify(status(),null,2)+'\n')
  process.exit(0)
}
const allowed:Record<string,Record<string,string>>={
  douyin:{plan:'easel_social.py',selftest:'easel_social.py',check:'easel_social.py',login:'easel_social.py',whoami:'easel_social.py','publish-video':'easel_social.py'},
  zhihu:{plan:'easel_social.py',check:'easel_social.py',selftest:'easel_social.py',whoami:'easel_social.py',login:'easel_social.py',publish:'easel_social.py',inspect:'easel_article.py','publish-article':'easel_zhihu_article.py'},
  video:{process:'easel_cli.py'},
}
const [area,action,...rest]=args
const script=allowed[area]?.[action]
if(!script){
  process.stderr.write('用法：easel status | easel douyin <plan|check|login|whoami|publish-video> | easel zhihu <plan|check|login|whoami|inspect|publish|publish-article> | easel video process\n')
  process.exit(2)
}
const {python,env}=runtimeEnv()
const scriptArgs=area==='zhihu'&&action==='inspect'?['inspect',...rest]:area==='zhihu'&&action==='publish-article'?rest:area==='video'?['process',...rest]:[area,action,...rest]
const child=spawn(python,[join(bundleRoot,'runtime',script),...scriptArgs],{env,cwd:process.cwd(),stdio:'inherit'})
child.on('error',error=>{process.stderr.write(String(error)+'\n');process.exitCode=1})
child.on('exit',code=>{process.exitCode=code??1})
