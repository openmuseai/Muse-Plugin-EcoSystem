import {readFile} from 'node:fs/promises'
import {createHash, createPublicKey, verify} from 'node:crypto'
import JSZip from 'jszip'

export async function verifyPackage(bytes, publicKeyPem, expectedKeyId) {
  if (bytes.length > 128 * 1024 * 1024) throw new Error('PACKAGE_BUDGET_EXCEEDED')
  const zip = await JSZip.loadAsync(bytes)
  const names = Object.keys(zip.files).filter(name => !zip.files[name].dir).sort()
  if (names.length > 256 || names.some(name => name.startsWith('/') || name.includes('..') || name.includes('\\'))) {
    throw new Error('UNSAFE_PACKAGE_PATH')
  }
  const required = name => zip.file(name) ?? (() => { throw new Error(`MISSING_FILE:${name}`) })()
  const catalogBytes = await required('catalog.json').async('nodebuffer')
  const signature = JSON.parse(await required('catalog.signature.json').async('string'))
  const key = createPublicKey(publicKeyPem)
  if (key.asymmetricKeyType !== 'ed25519' || signature.algorithm !== 'Ed25519' ||
      signature.keyId !== expectedKeyId ||
      !verify(null, catalogBytes, key, Buffer.from(signature.signature, 'base64'))) {
    throw new Error('INVALID_SIGNATURE')
  }
  const catalog = JSON.parse(catalogBytes.toString('utf8'))
  if (catalog.profile !== 'openmuse-signed-resources/1' || catalog.productId !== 'io.openmuse/pdf' ||
      !Array.isArray(catalog.entries)) throw new Error('INVALID_CATALOG')
  const listed = catalog.entries.map(entry => entry.path).sort()
  if (new Set(listed).size !== listed.length ||
      JSON.stringify(names) !== JSON.stringify([...listed, 'catalog.json', 'catalog.signature.json'].sort())) {
    throw new Error('PACKAGE_FILE_SET_MISMATCH')
  }
  let total = 0
  for (const entry of catalog.entries) {
    const data = await required(entry.path).async('nodebuffer')
    total += data.length
    if (total > 128 * 1024 * 1024 || data.length !== entry.bytes ||
        createHash('sha256').update(data).digest('hex') !== entry.sha256) {
      throw new Error(`INVALID_FILE_DIGEST:${entry.path}`)
    }
  }
  const manifest = JSON.parse(await required('manifest.json').async('string'))
  const product = JSON.parse(await required('product/product.json').async('string'))
  if (manifest.version !== catalog.version || product.version !== catalog.version ||
      product.id !== catalog.productId) throw new Error('VERSION_MISMATCH')
  return {id: catalog.productId, version: catalog.version, keyId: signature.keyId, files: listed.length}
}

if (process.argv[1]?.endsWith('/verify.mjs')) {
  const [, , packagePath, publicKeyPath, keyId] = process.argv
  if (!packagePath || !publicKeyPath || !keyId) {
    throw new Error('usage: npm run verify -- <package.mcpb> <trusted-ed25519-public.pem> <key-id>')
  }
  console.log(JSON.stringify(await verifyPackage(await readFile(packagePath), await readFile(publicKeyPath), keyId)))
}
