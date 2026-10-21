import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'
import { McpServer } from '@modelcontextprotocol/server'
import { serveStdio } from '@modelcontextprotocol/server/stdio'
import { z } from 'zod'

export const pdfContract={
  id:'https://plugins.openmuseai.com/contracts/pdfjs/pdf-read/v1',version:'1.0.1',
  title:'PDF.js · file snapshots',mediaType:'application/pdf',
  operations:{readSnapshot:'pdf_read_snapshot'},tools:['pdf_read_snapshot'],
  semantics:'Read the text layer of an authorized PDF. no-text-layer requires a separate OCR provider; no fabricated text.'}
const outputSchema=z.object({name:z.string(),revision:z.string(),pageCount:z.number().int(),
  status:z.enum(['text','no-text-layer']),pages:z.array(z.object({index:z.number().int(),text:z.string(),width:z.number(),height:z.number(),rotation:z.number()})),source:z.literal('pdfjs-dist')})
export async function readPdf(content:string,name='PDF document') {
  if(content.length>45*1024*1024)throw Error('FILE_TOO_LARGE_OR_EMPTY')
  const bytes=Buffer.from(content,'base64')
  if(!bytes.length||bytes.length>32*1024*1024)throw Error('FILE_TOO_LARGE_OR_EMPTY')
  if(bytes.toString('base64')!==content)throw Error('INVALID_BASE64')
  const {getDocument}=await import('pdfjs-dist/legacy/build/pdf.mjs')
  const task=getDocument({data:new Uint8Array(bytes),useSystemFonts:false,useWasm:false,
    standardFontDataUrl:fileURLToPath(new URL('./node_modules/pdfjs-dist/standard_fonts/',import.meta.url)),cMapUrl:fileURLToPath(new URL('./node_modules/pdfjs-dist/cmaps/',import.meta.url)),cMapPacked:true})
  const doc=await task.promise
  try {
    if(doc.numPages>500)throw Error('PAGE_BUDGET_EXCEEDED')
    const pages=[];let length=0
    for(let i=1;i<=doc.numPages;i++) {
      const page=await doc.getPage(i),viewport=page.getViewport({scale:1}),text=await page.getTextContent()
      const value=text.items.map((t:any)=>t.str===undefined?'':t.str+(t.hasEOL?'\n':' ')).join('').trim()
      length+=value.length;if(length>1024*1024)throw Error('TEXT_BUDGET_EXCEEDED')
      pages.push({index:i-1,text:value,width:viewport.width,height:viewport.height,rotation:viewport.rotation})
    }
    return outputSchema.parse({name,revision:createHash('sha256').update(bytes).digest('hex'),pageCount:doc.numPages,
      status:pages.some(p=>p.text.trim())?'text':'no-text-layer',pages,source:'pdfjs-dist'})
  } finally {await task.destroy()}
}
export function buildServer() {
  const server=new McpServer({name:'io.openmuse/pdf-reader',version:'0.1.1'},{capabilities:{tools:{},resources:{}}})
  server.registerResource('PDF public contracts','capability://pdf-reader/contracts',
    {mimeType:'application/vnd.openmuse.capabilities+json'},async()=>({contents:[{uri:'capability://pdf-reader/contracts',mimeType:'application/vnd.openmuse.capabilities+json',text:JSON.stringify({profile:'openmuse-capabilities/1',contracts:[pdfContract]})}]}))
  server.registerTool('pdf_read_snapshot',{description:'Read actual PDF text with Mozilla PDF.js; encrypted and malformed files fail explicitly.',
    inputSchema:z.object({content:z.string().max(45*1024*1024).meta({contentEncoding:'base64',contentMediaType:'application/pdf'}),name:z.string().max(180).optional()}),
    outputSchema,annotations:{readOnlyHint:true,openWorldHint:false}},async({content,name})=>{
      const output=await readPdf(content,name)
      return {content:[{type:'text',text:JSON.stringify(output)}],structuredContent:output}
    })
  return server
}
if(process.argv[1]?.endsWith('/server.mjs'))serveStdio(buildServer)
