import {readFile} from 'node:fs/promises'
import {readFileSync} from 'node:fs'
import {McpServer} from '@modelcontextprotocol/server'
import {serveStdio} from '@modelcontextprotocol/server/stdio'

const resources = ['product.json', 'chrome.json', 'commands.json', 'features.json']
const product = JSON.parse(readFileSync(new URL('./product/product.json', import.meta.url), 'utf8'))
export function buildServer() {
const server = new McpServer({name: 'io.openmuse/spreadsheet', version: product.version}, {capabilities: {resources: {}}})
for (const file of resources) {
  const uri = `capability://io.openmuse/spreadsheet-product/v1/${file}`
  server.registerResource(file, uri, {mimeType: 'application/vnd.openmuse.spreadsheet-product+json'}, async () => ({
    contents: [{uri, mimeType: 'application/vnd.openmuse.spreadsheet-product+json',
      text: await readFile(new URL(`./product/${file}`, import.meta.url), 'utf8')}]
  }))
}
return server
}
if (process.argv[1]?.endsWith('/server.mjs')) serveStdio(buildServer)
