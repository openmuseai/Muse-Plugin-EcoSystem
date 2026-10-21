import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {resolve} from 'node:path'
import {Client} from '@modelcontextprotocol/client'
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio'
for(const item of [
 {server:'plugins/genoffice-pptx/dist/server.mjs',tool:'slides_read_snapshot',file:'plugins/genoffice-pptx/dist/sample.pptx',pages:23,source:'genoffice-pptx-engine'},
 {server:'plugins/pdf-reader/dist/server.mjs',tool:'pdf_read_snapshot',file:'plugins/pdf-reader/fixtures/quarterly-brief.pdf',pages:2,source:'pdfjs-dist'},
])test('real provider release: '+item.tool,async()=>{
 const client=new Client({name:'devkit-contract-tck',version:'0.1.0'})
 const transport=new StdioClientTransport({command:process.execPath,args:[resolve(item.server)]})
 try{
  await client.connect(transport,{mode:'auto'})
  const tools=(await client.listTools()).tools,tool=tools.find(t=>t.name===item.tool)!
  assert.ok(tool.outputSchema);assert.equal((tool.inputSchema.properties as any).content.contentEncoding,'base64')
  const result=await client.callTool({name:item.tool,arguments:{content:(await readFile(item.file)).toString('base64'),name:'Fixture'}})
  assert.notEqual(result.isError,true);const value=result.structuredContent as any
  assert.equal(value.pageCount,item.pages);assert.equal(value.source,item.source);assert.equal(value.status,'text');assert.ok(value.pages.some((p:any)=>p.text.length>10))
  const resources=(await client.listResources()).resources;assert.ok(resources.some(r=>r.mimeType==='application/vnd.openmuse.capabilities+json'))
  const invalid=await client.callTool({name:item.tool,arguments:{content:Buffer.from('not a document').toString('base64')}})
  assert.equal(invalid.isError,true)
 }finally{await transport.close()}
})
