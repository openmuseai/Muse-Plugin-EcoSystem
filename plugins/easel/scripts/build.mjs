import {build} from 'esbuild'
import {mkdir,readFile,writeFile} from 'node:fs/promises'
import {resolve} from 'node:path'
const root=resolve(import.meta.dirname,'..')
await mkdir(resolve(root,'dist'),{recursive:true})
await build({entryPoints:[resolve(root,'src/server.ts')],bundle:true,platform:'node',format:'esm',target:'node22',outfile:resolve(root,'dist/server.mjs')})
await build({entryPoints:[resolve(root,'src/cli.ts')],bundle:true,platform:'node',format:'esm',target:'node22',outfile:resolve(root,'dist/cli.mjs')})
const result=await build({entryPoints:[resolve(root,'web/main.ts')],bundle:true,platform:'browser',format:'iife',target:'safari17',write:false,minify:true})
const template=await readFile(resolve(root,'web/index.html'),'utf8')
await writeFile(resolve(root,'dist/index.html'),template.replace('<!--SCRIPT-->',()=>`<script>${result.outputFiles[0].text.replaceAll('</script','<\\/script')}</script>`))
