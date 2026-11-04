import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const source = fs.readFileSync(path.resolve(root,
  '../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/style-gallery.ts'), 'utf8')
const ribbon = JSON.parse(fs.readFileSync(path.join(root, 'product/ribbon.json'), 'utf8'))
const menus = JSON.parse(fs.readFileSync(path.join(root, 'product/menus.json'), 'utf8'))

const block = source.match(/export const FALLBACK_STYLES:[\s\S]*?\[\s*([\s\S]*?)\s*\]\.map\(/u)?.[1]
if (!block) throw new Error('GenOffice quick style fallback source not found')
const field = (body, key) => body.match(new RegExp(`\\b${key}:\\s*([^,\\n}]+)`, 'u'))?.[1]?.trim()
const unquote = value => value?.replace(/^['"]|['"]$/gu, '')
const sourceStyles = [...block.matchAll(/\{([^{}]*)\}/gu)].map(([, body]) => ({
  styleId: unquote(field(body, 'styleId')),
  name: unquote(field(body, 'name')),
  type: unquote(field(body, 'type')),
  isDefault: field(body, 'isDefault') === 'true',
  qFormat: field(body, 'qFormat') === 'true',
  uiPriority: Number(field(body, 'uiPriority') ?? '0'),
}))
const group = ribbon.tabs.find(tab => tab.id === 'home')?.groups.find(g => g.id === 'styles')
const gallery = menus.menus['home.styles']?.find(node => node.id === 'home.styles.gallery')
if (group?.gallerySource !== 'document.quickStyles' || gallery?.presentation !== 'styleGallery' ||
    gallery.columns !== 5 || sourceStyles.length !== 4 || gallery.children?.length !== 4) {
  throw new Error('Dynamic quick style gallery contract drifted')
}
for (let i = 0; i < sourceStyles.length; i++) {
  const expected = sourceStyles[i]
  const actual = gallery.children[i].styleInfo
  for (const key of Object.keys(expected)) {
    if ((actual?.[key] ?? (key === 'uiPriority' ? 0 : false)) !== expected[key]) {
      throw new Error(`Quick style fallback mismatch at ${i}: ${key}`)
    }
  }
}
console.log(JSON.stringify({source: 'GenOffice style-gallery.ts', styles: sourceStyles.length,
  gallerySource: group.gallerySource, columns: gallery.columns}))
