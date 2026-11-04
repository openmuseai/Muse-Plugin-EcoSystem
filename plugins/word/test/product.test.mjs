import test from 'node:test'
import assert from 'node:assert/strict'
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises'
import {execFileSync} from 'node:child_process'
import {generateKeyPairSync} from 'node:crypto'
import os from 'node:os'
import path from 'node:path'
import JSZip from 'jszip'
import {Client} from '@modelcontextprotocol/client'
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio'
import {root, validateSource, validateProductData} from '../scripts/validate.mjs'
import {verifyPackage} from '../scripts/verify.mjs'
import {countWords} from '../src/word_count.mjs'

async function sourceData() {
  const read = async relative => JSON.parse(await readFile(path.join(root, relative), 'utf8'))
  const product = await read('product/product.json')
  return {
    product,
    commands: await read(product.resources.commands),
    ribbon: await read(product.resources.ribbon),
    menus: await read(product.resources.menus),
    chrome: await read(product.resources.chrome),
    icons: await read(product.resources.icons),
    shortcuts: await read(product.resources.shortcuts),
    features: await read(product.resources.features),
    fonts: await read(product.resources.fonts),
    templates: await Promise.all(product.resources.templates.map(read)),
    extensions: await Promise.all(product.resources.extensions.map(read))
  }
}

test('product resources have valid references and capability gates', async () => {
  const result = await validateSource()
  assert.equal(result.commands, 22)
  const data = await sourceData()
  assert.equal(data.commands.commands.find(c => c.id === 'word.tools.wordCount')?.target, 'editor')
  assert.equal(data.commands.commands.find(c => c.id === 'word.tools.extensionCount')?.target, 'extension')
  assert.equal(data.commands.commands.find(c => c.id === 'word.navigation.goTo')?.effect, 'view')
  assert.equal(data.commands.commands.find(c => c.id === 'word.view.readMode')?.target, 'editor')
  assert.equal(data.commands.commands.find(c => c.id === 'word.view.printLayout')?.effect, 'view')
  assert.equal(data.commands.commands.find(c => c.id === 'word.view.darkMode')?.operation, 'word.view.darkMode.toggle')
  assert.equal(data.commands.commands.find(c => c.id === 'word.view.ruler')?.operation, 'word.view.ruler.toggle')
  const view = data.ribbon.tabs.find(tab => tab.id === 'view')
  assert.deepEqual(view.groups.map(group => group.id),
    ['views', 'zoom', 'appearance', 'show', 'window'])
  assert.equal(view.groups.find(group => group.id === 'show')?.items.find(item =>
    item.id === 'gridlines')?.command, 'word.view.gridlines')
  assert.equal(view.groups.find(group => group.id === 'zoom')?.items.find(item =>
    item.id === 'multi-page')?.command, 'word.view.fitMultiplePages')
  data.ribbon.tabs[0].groups[0].commands.push('word.command.missing')
  assert.throws(() => validateProductData(data), /unknown ribbon command/u)
  data.ribbon.tabs[0].groups[0].commands.pop()
  data.shortcuts.bindings.push({...data.shortcuts.bindings[0]})
  assert.throws(() => validateProductData(data), /duplicate shortcut/u)
  data.shortcuts.bindings.pop()
  data.ribbon.tabs[1].groups[3].items[4].command = 'word.command.missing'
  assert.throws(() => validateProductData(data), /invalid ribbon control/u)
  data.ribbon.tabs[1].groups[3].items[4].command = 'word.format.bold'
  data.ribbon.tabs[1].groups[0].items[0].menu = 'menu.missing'
  assert.throws(() => validateProductData(data), /invalid ribbon control/u)
  delete data.ribbon.tabs[1].groups[0].items[0].menu
  data.menus.menus['home.paste'].push({...data.menus.menus['home.paste'][0]})
  assert.throws(() => validateProductData(data), /invalid menu/u)
  data.menus.menus['home.paste'].pop()
  data.chrome.metrics.statusHeight = 0
  assert.throws(() => validateProductData(data), /invalid chrome metric/u)
  data.chrome.metrics.statusHeight = 24
  data.chrome.status.zoom.maxPercent = 900
  assert.throws(() => validateProductData(data), /invalid status zoom policy/u)
  data.chrome.status.zoom.maxPercent = 500
  data.chrome.status.statistics.rows[0].id = 'unknown'
  assert.throws(() => validateProductData(data), /invalid Word statistics dialog/u)
  data.chrome.status.statistics.rows[0].id = 'pages'
  data.chrome.status.goTo.title = ''
  assert.throws(() => validateProductData(data), /invalid Word Go To panel/u)
  data.chrome.status.goTo.title = '定位'
  data.icons.icons.save = '<svg><script>bad</script></svg>'
  assert.throws(() => validateProductData(data), /invalid signed icon/u)
  delete data.icons.icons.save
  data.menus.menus['insert.cover'][0].children[0].previewParas[1].shadingFill = 'javascript:bad'
  assert.throws(() => validateProductData(data), /invalid menu presentation/u)
  data.menus.menus['insert.cover'][0].children[0].previewParas[1].shadingFill = undefined
  data.menus.menus['insert.wordArt'][0].children[5].previewWordArt.outline.widthEmu = 999999
  assert.throws(() => validateProductData(data), /invalid menu presentation/u)
})

test('word count is explicit and budgeted', () => {
  assert.deepEqual(countWords('会议\nAction item 42'), {
    profile: 'word.count.v1', characters: 17, charactersNoWhitespace: 14,
    words: 5, paragraphs: 2
  })
  assert.throws(() => countWords('abc', 2), /TEXT_BUDGET_EXCEEDED/u)
})

test('signed MCPB verifies every resource and rejects tampering', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'word-product-test-'))
  const product = JSON.parse(await readFile(path.join(root, 'product/product.json'), 'utf8'))
  const generated = [`word-${product.version}.mcpb`, `word-${product.version}.mcpb.sha256`,
    'catalog.json', 'catalog.signature.json']
  const originals = await Promise.all(generated.map(async name =>
    readFile(path.join(root, 'dist', name)).catch(error => {
      if (error.code === 'ENOENT') return null
      throw error
    })))
  try {
    const keys = generateKeyPairSync('ed25519', {
      privateKeyEncoding: {type: 'pkcs8', format: 'pem'},
      publicKeyEncoding: {type: 'spki', format: 'pem'}
    })
    const privateKey = path.join(dir, 'private.pem')
    await writeFile(privateKey, keys.privateKey)
    execFileSync(process.execPath, ['scripts/pack.mjs', '--private-key', privateKey, '--key-id', 'test-key'], {cwd: root})
    const client = new Client({name: 'word-product-tck', version: '1.0.0'})
    await client.connect(new StdioClientTransport({command: process.execPath, args: [path.join(root, 'dist/server.mjs')]}))
    try {
      const resources = (await client.listResources()).resources
      assert.ok(resources.some(item => item.uri === 'capability://io.openmuse/word-product/v1/product'))
      assert.ok(resources.some(item => item.uri === 'capability://io.openmuse/word-product/v1/menus'))
      const productResource = await client.readResource({uri: 'capability://io.openmuse/word-product/v1/product'})
      assert.equal(JSON.parse(productResource.contents[0].text).id, 'io.openmuse/word')
      const result = await client.callTool({name: 'word_count_text', arguments: {text: '会议 Action'}})
      assert.equal(result.structuredContent.words, 3)
    } finally {
      await client.close()
    }
    const bytes = await readFile(path.join(root, `dist/word-${product.version}.mcpb`))
    const verified = await verifyPackage(bytes, keys.publicKey, 'test-key')
    assert.equal(verified.id, 'io.openmuse/word')
    assert.ok(verified.files >= 10)
    await assert.rejects(verifyPackage(bytes, keys.publicKey, 'another-key'), /INVALID_SIGNATURE/u)
    const zip = await JSZip.loadAsync(bytes)
    zip.file('product/ribbon.json', '{}')
    const tampered = await zip.generateAsync({type: 'nodebuffer'})
    await assert.rejects(verifyPackage(tampered, keys.publicKey, 'test-key'), /INVALID_FILE_DIGEST/u)
  } finally {
    for (let i = 0; i < generated.length; i++) {
      const file = path.join(root, 'dist', generated[i])
      if (originals[i] === null) await rm(file, {force: true})
      else await writeFile(file, originals[i])
    }
    await rm(dir, {recursive: true, force: true})
  }
})
