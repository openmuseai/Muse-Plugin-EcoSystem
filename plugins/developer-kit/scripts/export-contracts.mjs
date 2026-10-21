import {Client} from '@modelcontextprotocol/client'
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio'
import {mkdir,writeFile} from 'node:fs/promises'
import path from 'node:path'
for(const file of ['plugins/genoffice-pptx/dist/server.mjs','plugins/pdf-reader/dist/server.mjs']){
 const client=new Client({name:'public-contract-export',version:'0.1.0'})
 const transport=new StdioClientTransport({command:process.execPath,args:[path.resolve(file)]})
 try{
  await client.connect(transport,{mode:'auto'})
  const resources=(await client.listResources()).resources
  const catalog=resources.find(r=>r.mimeType==='application/vnd.openmuse.capabilities+json')
  const data=JSON.parse((await client.readResource({uri:catalog.uri})).contents[0].text)
  const tools=(await client.listTools()).tools
  for(const contract of data.contracts){
   const target=path.join('contracts/published',new URL(contract.id).pathname.replace('/contracts/',''))
   await mkdir(path.dirname(target),{recursive:true})
   await writeFile(target,JSON.stringify({profile:data.profile,contract,tools:tools.filter(t=>contract.tools.includes(t.name))},null,2)+'\n')
  }
 }finally{await transport.close()}
}
