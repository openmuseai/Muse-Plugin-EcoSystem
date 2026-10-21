import {build} from 'esbuild'
import {mkdir,readFile,writeFile,copyFile,stat,readdir} from 'node:fs/promises'
import path from 'node:path'
const out='plugins/developer-kit/dist'
const metas=[]
const compile=async options=>{const result=await build({...options,metafile:true});metas.push(result.metafile);return result}
await mkdir(out+'/template',{recursive:true});await mkdir(out+'/web',{recursive:true})
await compile({entryPoints:['plugins/developer-kit/src/index.ts'],bundle:true,platform:'node',format:'esm',target:'node22',outfile:out+'/server.mjs'})
await compile({entryPoints:['templates/multi-resource/runtime.ts'],bundle:true,platform:'node',format:'esm',target:'node22',outfile:out+'/template/runtime.mjs'})
await compile({entryPoints:['templates/multi-resource/client.ts'],bundle:true,platform:'browser',format:'iife',target:'safari16',outfile:out+'/template/client.js'})
await compile({entryPoints:['packages/devkit-cli/src/index.ts'],bundle:true,platform:'node',format:'esm',target:'node22',outfile:out+'/cli.mjs'})
await writeFile(out+'/package.json',JSON.stringify({name:'@openmuse/developer-kit',version:'0.3.3',type:'module',bin:{muse:'cli.mjs'}}))
const web=await compile({entryPoints:['plugins/developer-kit/web/main.ts'],bundle:true,platform:'browser',format:'iife',target:'safari16',write:false})
await writeFile(out+'/web/index.html',(await readFile('plugins/developer-kit/web/index.html','utf8')).replace('<!--SCRIPT-->',()=>'<script>'+web.outputFiles[0].text.replaceAll('</script','<\\/script')+'</script>'))
await copyFile('templates/multi-resource/main.js',out+'/template/main.js')
await copyFile('templates/document-explainer/main.js',out+'/template/explainer-main.js')
await copyFile('plugins/document-explainer/web/index.html',out+'/template/explainer.html')
await compile({entryPoints:['templates/document-explainer/client.ts'],bundle:true,platform:'browser',format:'iife',target:'safari17',outfile:out+'/template/explainer-client.js',minify:true})
const packages=new Set()
for(const meta of metas)for(const input of Object.keys(meta.inputs)){
 if(!input.includes('node_modules/'))continue
 let directory=path.dirname(path.resolve(input))
 while(directory!==path.dirname(directory)){
  if(await stat(path.join(directory,'package.json')).catch(()=>null)){packages.add(directory);break}
  directory=path.dirname(directory)
 }
}
let notices=''
for(const directory of [...packages].sort()){
 const pkg=JSON.parse(await readFile(path.join(directory,'package.json'),'utf8'))
 const licenses=(await readdir(directory)).filter(name=>/^(LICENSE|LICENCE|COPYING|NOTICE)(\.|$)/i.test(name))
 let text=''
 for(const file of licenses)if((await stat(path.join(directory,file))).isFile())text+=await readFile(path.join(directory,file),'utf8')+'\n'
 if(!text)text='License identifier: '+pkg.license+'; '+(pkg.homepage??pkg.repository?.url??'')
 notices+=pkg.name+' '+pkg.version+'\n'+text+'\n\n'
}
await writeFile(out+'/template/THIRD-PARTY-NOTICES.txt',notices);await writeFile(out+'/THIRD-PARTY-NOTICES.txt',notices)
await writeFile(out+'/manifest.json',JSON.stringify({manifest_version:'0.3',name:'developer-kit',display_name:'OpenMuse Plugin DevKit',version:'0.3.3',description:'In-app multi-capability plugin development, real debugging and review submission.',author:{name:'OpenMuse contributors'},license:'MIT',compatibility:{platforms:['darwin'],runtimes:{node:'>=22.13.0'}},user_config:{project_directory:{type:'directory',title:'高级 MCP 工具项目根目录（可选）',description:'CLI 使用当前 Workspace，此项仅供直接调用 MCP 工程工具。',required:false,default:''},market_origin:{type:'string',title:'市场服务地址',default:'https://plugins.openmuseai.com',required:true},publisher_namespace:{type:'string',title:'开发者命名空间',default:'io.openmuse',required:true},developer_token:{type:'string',title:'开发者发布令牌',description:'仅交给插件后端用于提交待审；调试无需令牌。',sensitive:true,required:false}},server:{type:'node',entry_point:'server.mjs',mcp_config:{command:'node',args:['${__dirname}/server.mjs'],env:{PROJECT_DIRECTORY:'${user_config.project_directory}',MARKET_ORIGIN:'${user_config.market_origin}',PUBLISHER_NAMESPACE:'${user_config.publisher_namespace}',DEVELOPER_TOKEN:'${user_config.developer_token}'}}}}))
