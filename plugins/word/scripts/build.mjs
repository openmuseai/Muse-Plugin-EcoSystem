import {cp, mkdir, rm, writeFile} from 'node:fs/promises'
import path from 'node:path'
import {build} from 'esbuild'
import {root, validateSource} from './validate.mjs'

const identity = await validateSource()
const dist = path.join(root, 'dist')
await rm(dist, {recursive: true, force: true})
await mkdir(dist, {recursive: true})
await cp(path.join(root, 'product'), path.join(dist, 'product'), {recursive: true})
await cp(path.join(root, 'LICENSE'), path.join(dist, 'LICENSE'))
await mkdir(path.join(dist, 'extensions'), {recursive: true})
await cp(path.join(root, 'src/word_count.mjs'), path.join(dist, 'extensions/word_count.mjs'))
await build({
  entryPoints: [path.join(root, 'src/server.ts')],
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node22',
  outfile: path.join(dist, 'server.mjs')
})
await writeFile(path.join(dist, 'manifest.json'), JSON.stringify({
  manifest_version: '0.3',
  name: 'word',
  display_name: 'Word',
  version: identity.version,
  description: 'Signed Word product resources and explicit, read-only command extension. No document engine or editor UI.',
  author: {name: 'OpenMuse contributors'},
  license: 'MIT AND Apache-2.0',
  compatibility: {platforms: ['darwin', 'win32', 'linux'], runtimes: {node: '>=22.13.0'}},
  server: {type: 'node', entry_point: 'server.mjs', mcp_config: {
    command: 'node', args: ['${__dirname}/server.mjs']
  }}
}, null, 2) + '\n')
console.log(JSON.stringify({built: dist, ...identity}))
