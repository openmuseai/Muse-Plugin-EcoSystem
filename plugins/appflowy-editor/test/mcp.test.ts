import test from 'node:test'
import assert from 'node:assert/strict'
import { join } from 'node:path'
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client'
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio'

async function check(client: Client) {
  const tools = await client.listTools()
  const open = tools.tools.find(tool => tool.name === 'open_editor')
  assert.ok(open)
  assert.equal((open._meta as any).ui.resourceUri, 'ui://io.openmuse/appflowy-editor/document')
  const resource = await client.readResource({ uri: 'ui://io.openmuse/appflowy-editor/document' })
  assert.equal(resource.contents[0].mimeType, 'text/html;profile=mcp-app')
  assert.match((resource.contents[0] as any).text, /<iframe/)
  const result = await client.callTool({ name: 'open_editor', arguments: {} })
  assert.ok(result.content.some(item => item.type === 'resource_link' && item.uri.includes('/editor/')))
}

test('stdio package speaks standard MCP Apps', async () => {
  const client = new Client({ name: 'editor-tck', version: '1.0.0' })
  const transport = new StdioClientTransport({ command: process.execPath, args: [join(import.meta.dirname, '../dist/server.mjs')] })
  try {
    await client.connect(transport, { mode: 'auto' })
    await check(client)
    const tools = await client.listTools()
    const markdown = tools.tools.find(tool => tool.name === 'open_markdown')
    assert.ok(markdown)
    assert.equal((markdown.inputSchema.properties as any).content.contentEncoding, 'base64')
    assert.equal((markdown.inputSchema.properties as any).content.contentMediaType, 'text/markdown')
    const result = await client.callTool({
      name: 'open_markdown',
      arguments: { content: Buffer.from('# Review note\n').toString('base64'), name: 'review.md' },
    })
    assert.equal(result.isError, undefined)
    const link = result.content.find(item => item.type === 'resource_link') as any
    assert.ok(link)
    const payload = JSON.parse(Buffer.from(new URL(link.uri).hash.slice(6), 'base64url').toString())
    assert.deepEqual(payload, { name: 'review.md', content: '# Review note\n' })
  }
  finally { await transport.close() }
})

test('mobile remote endpoint speaks standard MCP Apps', async () => {
  const client = new Client({ name: 'editor-mobile-tck', version: '1.0.0' })
  const transport = new StreamableHTTPClientTransport(new URL('http://127.0.0.1:18789/mcp'))
  try { await client.connect(transport, { mode: 'auto' }); await check(client) }
  finally { await transport.close() }
})
