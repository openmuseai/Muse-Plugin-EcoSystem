import {readFile, writeFile} from 'node:fs/promises'
import path from 'node:path'
import vm from 'node:vm'
import {transform} from 'esbuild'
import {root} from './validate.mjs'

const source = path.resolve(root, '../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/editor/cover-pages.ts')
const output = path.join(root, 'product/menus.json')
const fixedDate = class extends Date {
  getFullYear() { return 4242 }
  toLocaleDateString() { return '__DATE__' }
}
const messages = {
  editorCoverTitle: '文档标题',
  editorCoverSubtitle: '文档副标题',
  editorCoverAuthor: '作者',
}
const transformed = await transform(await readFile(source, 'utf8'), {
  loader: 'ts', format: 'cjs', target: 'es2022',
})
const module = {exports: {}}
vm.runInNewContext(transformed.code, {
  module, exports: module.exports, Date: fixedDate,
  require: specifier => {
    if (specifier !== '../i18n/locale') throw new Error(`Unexpected GenOffice import: ${specifier}`)
    return {DATE_LOCALES: {'zh-CN': 'zh-CN'}, getLang: () => 'zh-CN',
      t: key => messages[key] ?? key}
  },
}, {filename: source, timeout: 2000})

const presets = module.exports.COVER_PRESETS
if (!Array.isArray(presets) || presets.length !== 12) throw new Error('GenOffice cover presets changed')
const menu = JSON.parse(await readFile(output, 'utf8'))
const gallery = menu.menus['insert.cover']?.find(entry => entry.id === 'insert.cover.gallery')
if (!gallery || gallery.presentation !== 'cardGallery' || gallery.children?.length !== 12) {
  throw new Error('Word cover gallery schema changed')
}
const allowed = new Set(['text', 'bold', 'italic', 'color', 'sizeHalfPoints', 'align',
  'spaceBefore', 'spaceAfter', 'shadingFill', 'borders', 'indentLeft', 'indentRight'])
for (let index = 0; index < presets.length; index++) {
  const preset = presets[index]
  const cell = gallery.children[index]
  if (cell.id !== `insert.cover.${preset.id}`) throw new Error(`Cover order changed at ${index}`)
  const paragraphs = preset.paras.map(para => {
    if (Object.keys(para).some(key => !allowed.has(key))) throw new Error(`Unknown cover property: ${preset.id}`)
    return Object.fromEntries(Object.entries(para).map(([key, value]) =>
      [key, key === 'text' ? value.replaceAll('4242', '{year}').replaceAll('__DATE__', '{date}') : value]))
  })
  if (!paragraphs.length || paragraphs.length > 8) throw new Error(`Invalid cover: ${preset.id}`)
  cell.previewParas = paragraphs
}
const rendered = JSON.stringify(menu, null, 2) + '\n'
if (process.argv.includes('--write')) {
  await writeFile(output, rendered)
  console.log(JSON.stringify({written: output, covers: presets.length}))
} else {
  const checked = await readFile(output, 'utf8')
  if (checked !== rendered) throw new Error('GenOffice cover previews are stale; run npm run sync:cover-previews')
  console.log(JSON.stringify({checked: output, covers: presets.length}))
}
