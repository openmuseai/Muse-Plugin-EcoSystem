import {build} from 'esbuild';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
const base=new URL('../',import.meta.url);
const bridgeBuild=await build({metafile:true,entryPoints:[new URL('web/bridge.ts',base).pathname],bundle:true,platform:'browser',format:'iife',target:'safari17',outfile:new URL('web/bridge.js',base).pathname,minify:true});
let html=await readFile(new URL('web/index.html',base),'utf8');
for(const name of ['styles','workflow','lifecycle']){const css=await readFile(new URL(`web/${name}.css`,base),'utf8');html=html.replace(`<link rel="stylesheet" href="${name}.css">`,()=>'<style>'+css+'</style>');}
for(const name of ['model','graph-model','bridge','runtime','lifecycle','workflow','live-app','app']){const source=await readFile(new URL(`web/${name}.js`,base),'utf8');html=html.replace(`<script defer src="${name}.js"></script>`,'');html=html.replace('</body>',()=>'<script>'+source.replaceAll('</script','<\\/script')+'</script></body>');}
await mkdir(new URL('dist/',base),{recursive:true});await writeFile(new URL('dist/bridge-inputs.json',base),JSON.stringify(Object.keys(bridgeBuild.metafile.inputs)));await writeFile(new URL('dist/index.html',base),html);
process.stdout.write('Built dist/index.html (MCP Apps UI artifact; local demo and service adapters)\n');
