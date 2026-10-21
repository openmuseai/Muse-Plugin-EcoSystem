import {build} from 'esbuild'
import {mkdir,readFile,writeFile} from 'node:fs/promises'
const out='plugins/document-explainer/dist'
await mkdir(out+'/web',{recursive:true})
await build({entryPoints:['plugins/document-explainer/src/server.ts'],bundle:true,platform:'node',format:'esm',target:'node22',outfile:out+'/server.mjs'})
const web=await build({entryPoints:['plugins/document-explainer/web/entry.ts'],bundle:true,platform:'browser',format:'iife',target:'safari17',minify:true,write:false})
await writeFile(out+'/web/index.html',(await readFile('plugins/document-explainer/web/index.html','utf8')).replace('<!--SCRIPT-->',()=>'<script>'+web.outputFiles[0].text.replaceAll('</script','<\\/script')+'</script>'))
await writeFile(out+'/manifest.json',JSON.stringify({manifest_version:'0.3',name:'document-explainer',display_name:'文档讲解',version:'0.2.1',description:'PPTX and PDF live narration toolbar. Uses the configured DSH Agent; no document engine bundled.',author:{name:'OpenMuse contributors'},license:'MIT',compatibility:{platforms:['darwin'],runtimes:{node:'>=22.13.0'}},server:{type:'node',entry_point:'server.mjs',mcp_config:{command:'node',args:['${__dirname}/server.mjs']}}}))

const {exportOffline}=await import('../../packages/plugin-sdk/scripts/export-offline.mjs')
await exportOffline(out+'/server.mjs',out+'/web/mcp-offline.json')
