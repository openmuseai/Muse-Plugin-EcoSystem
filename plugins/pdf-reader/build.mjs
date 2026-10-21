import {build} from 'esbuild'
import {mkdir,cp,writeFile,readFile} from 'node:fs/promises'
await mkdir('plugins/pdf-reader/dist/web',{recursive:true})
const web=await build({entryPoints:['plugins/pdf-reader/web/main.ts'],bundle:true,platform:'browser',format:'iife',target:'safari17',write:false,minify:true})
await writeFile('plugins/pdf-reader/dist/web/index.html',(await readFile('plugins/pdf-reader/web/index.html','utf8')).replace('<!--SCRIPT-->',()=>'<script>'+web.outputFiles[0].text.replaceAll('</script','<\\/script')+'</script>'))
await build({entryPoints:['plugins/pdf-reader/src/index.ts'],bundle:true,platform:'node',format:'esm',target:'node22',external:['pdfjs-dist/*'],outfile:'plugins/pdf-reader/dist/server.mjs'})
for(const name of ['pdfjs-dist','@napi-rs/canvas','@napi-rs/canvas-darwin-arm64']) {
 await cp('node_modules/'+name,'plugins/pdf-reader/dist/node_modules/'+name,{recursive:true})
}
await writeFile('plugins/pdf-reader/dist/manifest.json',JSON.stringify({manifest_version:'0.3',name:'pdf-reader',display_name:'PDF Reader',version:'0.2.0',description:'Mozilla PDF.js text-layer capability for independent plugins. No OCR or document upload.',author:{name:'OpenMuse contributors'},license:'Apache-2.0',compatibility:{platforms:['darwin'],runtimes:{node:'>=22.13.0'}},server:{type:'node',entry_point:'server.mjs',mcp_config:{command:'node',args:['${__dirname}/server.mjs']}}}))
