import {readFile} from 'node:fs/promises'
import {McpServer} from '@modelcontextprotocol/server'
import {serveStdio} from '@modelcontextprotocol/server/stdio'
import {z} from 'zod'
import {countWords} from './word_count.mjs'

// Desktop discovery only. The Host renders the editor and owns the document.
// Mobile/Web read the same signed product files from the installed package.
const resources = [
  ['product', 'product/product.json'],
  ['commands', 'product/commands.json'],
  ['ribbon', 'product/ribbon.json'],
  ['menus', 'product/menus.json'],
  ['chrome', 'product/chrome.json'],
  ['icons', 'product/icons.json'],
  ['shortcuts', 'product/shortcuts.json'],
  ['features', 'product/features.json'],
  ['fonts', 'product/fonts/catalog.json'],
  ['template-meeting-notes', 'product/templates/meeting-notes.json'],
  ['template-report', 'product/templates/report.json'],
  ['extension-word-count', 'product/extensions/word-count.json']
] as const

export function buildServer() {
  const server = new McpServer(
    {name: 'io.openmuse/word', version: '0.1.22'},
    {capabilities: {resources: {}, tools: {}}}
  )
  for (const [name, file] of resources) {
    const uri = `capability://io.openmuse/word-product/v1/${name}`
    server.registerResource(name, uri,
      {mimeType: 'application/vnd.openmuse.word-product+json'},
      async () => ({contents: [{
        uri,
        mimeType: 'application/vnd.openmuse.word-product+json',
        text: await readFile(new URL(`./${file}`, import.meta.url), 'utf8')
      }]})
    )
  }
  server.registerTool('word_count_text', {
    description: 'Count an explicitly provided, authorized text snapshot. Read-only; never called for each keystroke.',
    inputSchema: z.object({text: z.string().max(1_000_000)}),
    outputSchema: z.object({
      profile: z.literal('word.count.v1'),
      characters: z.number().int(),
      charactersNoWhitespace: z.number().int(),
      words: z.number().int(),
      paragraphs: z.number().int()
    }),
    annotations: {readOnlyHint: true, openWorldHint: false}
  }, async ({text}) => {
    const result = countWords(text)
    return {content: [{type: 'text', text: JSON.stringify(result)}], structuredContent: result}
  })
  return server
}

if (process.argv[1]?.endsWith('/server.mjs')) serveStdio(buildServer)
