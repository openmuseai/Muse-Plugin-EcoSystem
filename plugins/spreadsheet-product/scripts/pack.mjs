import {readFile, readdir, writeFile} from 'node:fs/promises'
import path from 'node:path'
import {createHash, createPrivateKey, sign} from 'node:crypto'
import JSZip from 'jszip'
import {root} from './validate.mjs'

const arg = name => {
  const i = process.argv.indexOf(name)
  return i < 0 ? null : process.argv[i + 1]
}
const privateKeyPath = arg('--private-key')
const keyId = arg('--key-id')
if (!privateKeyPath || !keyId || !/^[A-Za-z0-9._-]{1,80}$/u.test(keyId)) {
  throw new Error('usage: npm run pack -- --private-key /secure/ed25519.pem --key-id publisher-key-id')
}

// Always sign a fresh build, so stale dist files cannot be published.
await import('./build.mjs')
const dist = path.join(root, 'dist')
const product = JSON.parse(await readFile(path.join(dist, 'product/product.json'), 'utf8'))
const files = []
async function walk(relative = '') {
  for (const entry of (await readdir(path.join(dist, relative), {withFileTypes: true})).sort((a, b) => a.name.localeCompare(b.name))) {
    const name = path.posix.join(relative, entry.name)
    if (entry.isSymbolicLink()) throw new Error(`symlink forbidden: ${name}`)
    if (entry.isDirectory()) await walk(name)
    else if (!name.endsWith('.mcpb') && !name.endsWith('.sha256') &&
      !['catalog.json', 'catalog.signature.json'].includes(name)) files.push(name)
  }
}
await walk()
const entries = []
for (const file of files.sort()) {
  const bytes = await readFile(path.join(dist, file))
  entries.push({path: file, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')})
}
const catalog = Buffer.from(JSON.stringify({
  profile: 'openmuse-signed-resources/1',
  productId: product.id,
  version: product.version,
  entries
}) + '\n')
const key = createPrivateKey(await readFile(privateKeyPath))
if (key.asymmetricKeyType !== 'ed25519') throw new Error('Ed25519 private key required')
const signature = sign(null, catalog, key).toString('base64')
await writeFile(path.join(dist, 'catalog.json'), catalog)
await writeFile(path.join(dist, 'catalog.signature.json'), JSON.stringify({
  algorithm: 'Ed25519', keyId, signature
}) + '\n')
const zip = new JSZip()
for (const file of [...files, 'catalog.json', 'catalog.signature.json']) {
  zip.file(file, await readFile(path.join(dist, file)), {date: new Date('2020-01-01T00:00:00Z'), createFolders: false})
}
const bytes = await zip.generateAsync({type: 'nodebuffer', compression: 'DEFLATE', compressionOptions: {level: 6}})
const output = path.join(dist, `spreadsheet-${product.version}.mcpb`)
await writeFile(output, bytes)
const sha256 = createHash('sha256').update(bytes).digest('hex')
await writeFile(output + '.sha256', sha256 + '\n')
console.log(JSON.stringify({file: output, sha256, bytes: bytes.length, keyId}))
