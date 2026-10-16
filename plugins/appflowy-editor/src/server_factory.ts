import { McpServer } from '@modelcontextprotocol/server'
import { z } from 'zod'

export const editorUiUri = 'ui://io.openmuse/appflowy-editor/document'
export const editorMime = 'text/html;profile=mcp-app'

function editorUrl(): string {
  const raw = process.env.EDITOR_PUBLIC_URL || 'http://127.0.0.1:8768/editor/'
  const url = new URL(raw)
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname))) {
    throw new Error('Editor URL must use HTTPS or loopback HTTP')
  }
  return url.href
}

export function buildServer() {
  const server = new McpServer({ name: 'io.openmuse/appflowy-editor', version: '0.1.4' }, { capabilities: { tools: {}, resources: {} } })
  server.registerResource('AppFlowy Editor', editorUiUri,
    { title: 'AppFlowy Editor', mimeType: editorMime },
    async () => {
      const url = editorUrl()
      const origin = new URL(url).origin
      const text = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AppFlowy Editor</title><style>html,body,iframe{margin:0;width:100%;height:100%;border:0;background:#f7f6f3}</style></head><body><iframe title="AppFlowy Editor" sandbox="allow-scripts allow-same-origin allow-downloads" src="${url.replaceAll('&', '&amp;').replaceAll('"', '&quot;')}"></iframe></body></html>`
      return { contents: [{ uri: editorUiUri, mimeType: editorMime, text, _meta: { ui: { csp: { frameDomains: [origin] } } } }] }
    })
  server.registerTool('open_editor', {
    title: 'Open AppFlowy Editor',
    description: 'Open a rich text document editor based on AppFlowy Editor.',
    inputSchema: z.object({}),
    _meta: { ui: { resourceUri: editorUiUri } },
  }, async () => ({ content: [
    { type: 'text' as const, text: 'Open AppFlowy Editor' },
    { type: 'resource_link' as const, uri: editorUrl(), name: 'AppFlowy Editor', mimeType: 'text/html' },
  ], _meta: { ui: { resourceUri: editorUiUri } } }))
  server.registerTool('open_markdown', {
    title: 'Open Markdown document',
    description: 'Open an authorized Markdown file in AppFlowy Editor as a locally saved document.',
    inputSchema: z.object({
      content: z.string().meta({ contentEncoding: 'base64', contentMediaType: 'text/markdown' }),
      name: z.string().max(180).optional(),
    }),
    _meta: { ui: { resourceUri: editorUiUri } },
  }, async ({ content, name }) => {
    const bytes = Buffer.from(content, 'base64')
    if (bytes.length > 32 * 1024 || bytes.toString('base64').replace(/=+$/, '') !== content.replace(/=+$/, '')) {
      throw new Error('Markdown content must be canonical base64 and at most 32 KiB')
    }
    const payload = Buffer.from(JSON.stringify({ name: name || 'Markdown 文档', content: bytes.toString('utf8') })).toString('base64url')
    const url = `${editorUrl()}#open=${payload}`
    return { content: [
      { type: 'resource_link' as const, uri: url, name: name || 'Markdown 文档', mimeType: 'text/html' },
    ], _meta: { ui: { resourceUri: editorUiUri } } }
  })
  return server
}
