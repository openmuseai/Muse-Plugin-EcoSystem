import {build} from 'esbuild'
import {mkdir,cp,writeFile} from 'node:fs/promises'
await mkdir('plugins/pdf-reader/dist',{recursive:true})
await build({entryPoints:['plugins/pdf-reader/src/index.ts'],bundle:true,platform:'node',format:'esm',target:'node22',external:['pdfjs-dist/*'],outfile:'plugins/pdf-reader/dist/server.mjs'})
for(const name of ['pdfjs-dist','@napi-rs/canvas','@napi-rs/canvas-darwin-arm64']) {
 await cp('node_modules/'+name,'plugins/pdf-reader/dist/node_modules/'+name,{recursive:true})
}
await writeFile('plugins/pdf-reader/dist/manifest.json',JSON.stringify({manifest_version:'0.3',name:'pdf-reader',display_name:'PDF Capability Provider',version:'0.1.1',description:'Mozilla PDF.js text-layer capability for independent plugins. No OCR or document upload.',author:{name:'OpenMuse contributors'},license:'Apache-2.0',compatibility:{platforms:['darwin'],runtimes:{node:'>=22.13.0'}},server:{type:'node',entry_point:'server.mjs',mcp_config:{command:'node',args:['${__dirname}/server.mjs']}}}))
