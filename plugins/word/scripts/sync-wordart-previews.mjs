import {readFile, writeFile} from 'node:fs/promises'
import path from 'node:path'
import vm from 'node:vm'
import {transform} from 'esbuild'
import {root} from './validate.mjs'

const source = path.resolve(root, '../genoffice-pptx/vendor/genoffice/packages/ui/src/wordart-presets.ts')
const output = path.join(root, 'product/menus.json')
const transformed = await transform(await readFile(source, 'utf8'), {
  loader: 'ts', format: 'cjs', target: 'es2022',
})
const module = {exports: {}}
vm.runInNewContext(transformed.code, {module, exports: module.exports}, {
  filename: source, timeout: 2000,
})

const presets = module.exports.WORDART_PRESETS
if (!Array.isArray(presets) || presets.length !== 12) throw new Error('GenOffice WordArt presets changed')
const menu = JSON.parse(await readFile(output, 'utf8'))
const gallery = menu.menus['insert.wordArt']?.find(entry => entry.id === 'insert.wordArt.gallery')
if (!gallery || gallery.presentation !== 'wordArtGallery' || gallery.columns !== 4 || gallery.children?.length !== 12) {
  throw new Error('WordArt gallery schema changed')
}
for (let index = 0; index < presets.length; index++) {
  const preset = presets[index]
  const cell = gallery.children[index]
  if (cell.id !== `insert.wordArt.${preset.id}` || cell.swatch !== preset.fill) {
    throw new Error(`WordArt ID/order/fill changed at ${index}`)
  }
  cell.previewWordArt = {
    fill: preset.fill,
    bold: preset.bold === true,
    italic: preset.italic === true,
    ...(preset.outline ? {outline: {
      color: preset.outline.color,
      widthEmu: preset.outline.widthEmu,
    }} : {}),
  }
}
const rendered = JSON.stringify(menu, null, 2) + '\n'
if (process.argv.includes('--write')) {
  await writeFile(output, rendered)
  console.log(JSON.stringify({written: output, presets: presets.length}))
} else {
  const checked = await readFile(output, 'utf8')
  if (checked !== rendered) throw new Error('GenOffice WordArt previews are stale; run npm run sync:wordart-previews')
  console.log(JSON.stringify({checked: output, presets: presets.length}))
}
