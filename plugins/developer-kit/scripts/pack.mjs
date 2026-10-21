import { readFile,writeFile,readdir } from 'node:fs/promises'
import path from 'node:path'
import JSZip from 'jszip'
import { createHash } from 'node:crypto'
const directory=process.argv[2]??'plugins/developer-kit/dist'
const manifest=JSON.parse(await readFile(path.join(directory,'manifest.json'),'utf8'))
const zip=new JSZip()
async function add(root,relative=''){
 for(const entry of (await readdir(path.join(root,relative),{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))){
  const name=path.posix.join(relative,entry.name)
  if(entry.isSymbolicLink())throw Error('Symlink in package')
  if(entry.isDirectory())await add(root,name)
  else if(!name.endsWith('.mcpb')&&!name.endsWith('.sha256'))zip.file(name,await readFile(path.join(root,name)),{date:new Date('2020-01-01T00:00:00Z'),createFolders:false})
 }
}
await add(directory)
const bytes=await zip.generateAsync({type:'nodebuffer',compression:'DEFLATE',compressionOptions:{level:6}})
const filename=path.join(directory,manifest.name+'-'+manifest.version+'.mcpb')
await writeFile(filename,bytes);const digest=createHash('sha256').update(bytes).digest('hex');await writeFile(filename+'.sha256',digest+'\n')
console.log(JSON.stringify({file:filename,sha256:digest,bytes:bytes.length}))
