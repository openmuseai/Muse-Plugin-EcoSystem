import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {join} from 'node:path'
import {Client} from '@modelcontextprotocol/client'
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio'

test('independent MCP client opens the setup surface without installing dependencies',async()=>{
  const root=join(import.meta.dirname,'..')
  const client=new Client({name:'easel-independent-test',version:'1.0.0'})
  const transport=new StdioClientTransport({command:process.execPath,args:[join(root,'dist/server.mjs')],env:{PATH:'/usr/bin:/bin'}})
  try{
    await client.connect(transport,{mode:'auto'})
    const tools=(await client.listTools()).tools
    assert.deepEqual(tools.map(t=>t.name).sort(),['easel_open','easel_setup_job','easel_setup_start','easel_setup_status'])
    const open=tools.find(t=>t.name==='easel_open')
    assert.equal(open._meta.ui.resourceUri,'ui://easel/setup')
    const result=await client.callTool({name:'easel_setup_status',arguments:{}})
    assert.equal(result.isError,undefined)
    assert.equal(typeof result.structuredContent.ready,'boolean')
    assert.equal((await client.callTool({name:'easel_open',arguments:{}})).isError,undefined)
    const page=await client.readResource({uri:'ui://easel/setup'})
    assert.match(page.contents[0].text,/Easel 安装向导/)
  }finally{await transport.close()}
})

test('packaged bundle has complete private social closure and reproducible digest',async()=>{
  const root=join(import.meta.dirname,'..')
  const bytes=await readFile(join(root,'dist/easel-0.5.0.mcpb'))
  const {createHash}=await import('node:crypto')
  const expected=(await readFile(join(root,'dist/mcpb.sha256'),'utf8')).split(' ')[0]
  assert.equal(createHash('sha256').update(bytes).digest('hex'),expected)
  const text=bytes.toString('latin1')
  for(const name of ['runtime/easel_social.py','runtime/easel_cli.py','shared/scripts/douyin_publish.py','shared/scripts/web_publisher.py','web/index.html','server/cli.mjs'])assert.ok(text.includes(name),name)
})
