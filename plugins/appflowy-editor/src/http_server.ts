import { createServer } from 'node:http'
import { readFile, stat } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, extname, resolve, sep } from 'node:path'
import { createMcpHandler } from '@modelcontextprotocol/server'
import { localhostHostValidation, localhostOriginValidation, toNodeHandler } from '@modelcontextprotocol/node'
import { buildServer } from './server_factory.js'

const handler = toNodeHandler(createMcpHandler(buildServer))
const localHost = localhostHostValidation()
const localOrigin = localhostOriginValidation()
const build = resolve(dirname(fileURLToPath(import.meta.url)), '../web/build/web')
const mime: Record<string,string> = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json','.png':'image/png','.svg':'image/svg+xml','.wasm':'application/wasm','.woff2':'font/woff2'}
const port = Number(process.env.PORT || 8768)
createServer(async (request,response) => {
  if (!localHost(request,response) || !localOrigin(request,response)) return
  const pathname = new URL(request.url || '/', `http://127.0.0.1:${port}`).pathname
  if (pathname === '/mcp') { void handler(request,response); return }
  if (!pathname.startsWith('/editor/')) { response.writeHead(404).end(); return }
  const relative = decodeURIComponent(pathname.slice('/editor/'.length)) || 'index.html'
  const candidate = resolve(build,relative)
  if (candidate !== build && !candidate.startsWith(build+sep)) { response.writeHead(400).end(); return }
  try {
    const file = (await stat(candidate)).isDirectory() ? resolve(candidate,'index.html') : candidate
    const body = await readFile(file)
    response.writeHead(200,{'content-type':mime[extname(file)] || 'application/octet-stream','cache-control':/\b(index\.html|flutter_bootstrap\.js)$/.test(file)?'no-cache':'public, max-age=3600','x-content-type-options':'nosniff'})
    response.end(body)
  } catch { response.writeHead(404).end() }
}).listen(port,'127.0.0.1',()=>process.stderr.write(`Editor MCP + Web on http://127.0.0.1:${port}\n`))
