import {readFile, writeFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))
const sourcePath = path.resolve(root, '../genoffice-pptx/vendor/genoffice/packages/ui/src/color-picker.tsx')
const chromePath = path.join(root, 'product/chrome.json')
const source = await readFile(sourcePath, 'utf8')
const chrome = JSON.parse(await readFile(chromePath, 'utf8'))

function section(name, next) {
  const start = source.indexOf(`export const ${name}:`)
  const end = next ? source.indexOf(`export const ${next}:`, start) : source.indexOf('export interface ColorPickerStrings', start)
  if (start < 0 || end <= start) throw new Error(`GenOffice palette section ${name} missing`)
  return source.slice(start, end)
}

function named(name, next) {
  return [...section(name, next).matchAll(/\{ name: '[^']+', hex: '([0-9A-F]{6})' \}/gu)]
    .map(match => `#${match[1].toLowerCase()}`)
}

const theme = named('THEME_COLORS', 'THEME_COLOR_SHADES')
const shades = [...section('THEME_COLOR_SHADES', 'STANDARD_COLORS').matchAll(/'([0-9A-F]{6})'/gu)]
  .map(match => `#${match[1].toLowerCase()}`)
const standard = named('STANDARD_COLORS')
if (theme.length !== 10 || shades.length !== 50 || standard.length !== 10) {
  throw new Error('GenOffice palette dimensions changed; review its component before syncing')
}

chrome.palette = {
  profile: 'openmuse-pdf-palette/1',
  theme,
  shades: Array.from({length: 5}, (_, row) => shades.slice(row * 10, row * 10 + 10)),
  standard,
  labels: {theme: '主题颜色', standard: '标准颜色', more: '更多颜色…'}
}
await writeFile(chromePath, `${JSON.stringify(chrome, null, 2)}\n`)
console.log(`Synced GenOffice color palette: ${theme.length + shades.length + standard.length} swatches`)
