import {readFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))
const sourceRoot = path.resolve(root, '../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/components')
const files = [
  'Ribbon.tsx',
  'ribbon-tabs.tsx',
  'ribbon-insert-tab.tsx',
  'ribbon-design-tab.tsx',
  'ribbon-layout-tab.tsx',
  'ribbon-references-tab.tsx',
  'ribbon-hf-tab.tsx',
]
const inventory = await readFile(path.join(root, 'docs/08-RIBBON-MENU-INVENTORY.zh-CN.md'), 'utf8')
const mappings = [...inventory.matchAll(/^\| `([^`]+)` \| `([^`]+)` \| `([^`]+)` \|/gmu)]
const mapped = new Map(mappings.map(([, file, key, id]) => [`${file}:${key}`, id]))
const source = new Set()
for (const file of files) {
  const content = await readFile(path.join(sourceRoot, file), 'utf8')
  for (const [, key] of content.matchAll(/dropdown\s*===\s*'([^']+)'/gu)) {
    source.add(`${file}:${key}`)
  }
}
const missing = [...source].filter(key => !mapped.has(key))
const stale = [...mapped.keys()].filter(key => !source.has(key))
const ribbon = JSON.parse(await readFile(path.join(root, 'product/ribbon.json'), 'utf8'))
const menus = JSON.parse(await readFile(path.join(root, 'product/menus.json'), 'utf8')).menus
const referenced = new Set()
for (const tab of ribbon.tabs) {
  if (tab.menu) referenced.add(tab.menu)
  for (const group of tab.groups) {
    if (group.gallerySource === 'document.quickStyles') referenced.add('home.styles')
    for (const item of group.items) if (item.menu) referenced.add(item.menu)
  }
}
const unbuilt = [...mapped.values()].filter(id => !menus[id] || !referenced.has(id))
const orphan = Object.keys(menus).filter(id => !referenced.has(id))
const insertSource = await readFile(path.join(sourceRoot, 'ribbon-insert-tab.tsx'), 'utf8')
const shapeSource = await readFile(path.resolve(sourceRoot, '../../../../../packages/ui/src/shape-gallery.tsx'), 'utf8')
const wordArtSource = await readFile(path.resolve(sourceRoot, '../../../../../packages/ui/src/wordart-presets.ts'), 'utf8')
const coverSource = await readFile(path.resolve(sourceRoot, '../editor/cover-pages.ts'), 'utf8')
const colorSource = await readFile(path.resolve(sourceRoot, '../../../../../packages/ui/src/color-picker.tsx'), 'utf8')
const listSource = await readFile(path.resolve(sourceRoot, '../list-presets.ts'), 'utf8')
const equationSource = await readFile(path.join(sourceRoot, 'EquationModal.tsx'), 'utf8')
const sourceCounts = {
  symbols: [...insertSource.match(/const SYMBOLS = \[([\s\S]*?)\]/u)?.[1].matchAll(/'[^']+'/gu) ?? []].length,
  shapes: [...shapeSource.matchAll(/\bs\('[^']+', '[^']+'\)/gu)].length,
  shapeGroups: [...shapeSource.matchAll(/\bgroupKey: '/gu)].length,
  wordArt: [...wordArtSource.matchAll(/\bid: '[^']+',\s*nameKey: '/gu)].length,
  covers: [...coverSource.matchAll(/\bpreset\('[^']+', 'editorCover/gu)].length,
  themeColors: [...colorSource.match(/THEME_COLORS[^=]*= \[([\s\S]*?)\]/u)?.[1].matchAll(/\bhex: '/gu) ?? []].length,
  shades: [...colorSource.match(/THEME_COLOR_SHADES[^=]*= \[([\s\S]*?)\n\]/u)?.[1].matchAll(/'[0-9A-F]{6}'/gu) ?? []].length,
  bullets: [...listSource.match(/BULLET_LIBRARY = \[([^\]]*)\]/u)?.[1].matchAll(/'[^']+'/gu) ?? []].length,
  numbers: [...listSource.match(/NUMBER_LIBRARY[^=]*= \[([\s\S]*?)\n\]/u)?.[1].matchAll(/\bnumFmt:/gu) ?? []].length,
  multilevel: [...listSource.match(/MULTILEVEL_LIBRARY[^=]*= \[([\s\S]*?)\n\]/u)?.[1].matchAll(/^  \/\/ /gmu) ?? []].length,
  equations: [...equationSource.match(/export const BUILTIN_EQUATIONS:[\s\S]*?= \[([\s\S]*?)\n\]/u)?.[1].matchAll(/nameKey: 'appEq[^']+'/gu) ?? []].length,
  dropCaps: [...insertSource.match(/className="dropcap-menu"([\s\S]*?)\.map\(\(opt\)/u)?.[1].matchAll(/\bval: (?:null|'[^']+')/gu) ?? []].length,
}
const productCounts = {
  symbols: menus['insert.symbol'][0].children.length,
  shapes: menus['insert.shapes'].reduce((n, group) => n + group.children.length, 0),
  shapeGroups: menus['insert.shapes'].length,
  wordArt: menus['insert.wordArt'][0].children.length,
  covers: menus['insert.cover'][0].children.length,
  themeColors: menus['home.fontColor'].find(node => node.id === 'home.fontColor.theme').children.length - 50,
  shades: menus['home.fontColor'].find(node => node.id === 'home.fontColor.theme').children.length - 10,
  bullets: menus['home.bullets'].find(node => node.id === 'bullets.gallery').children.length - 1,
  numbers: menus['home.numbering'].find(node => node.id === 'number.gallery').children.length - 1,
  multilevel: menus['home.multilevel'].find(node => node.id === 'multi.gallery').children.length,
  equations: menus['insert.equation'].find(node => node.id === 'equation.gallery').children.length,
  dropCaps: menus['insert.dropCap'].find(node => node.id === 'dropcap.gallery').children.length,
}
const galleryMismatches = Object.keys(sourceCounts).filter(key => sourceCounts[key] !== productCounts[key])
const flatMismatches = ['file', 'insert.pageNumber', 'context.hfPageNumber'].filter(
  id => menus[id].some(node => node.kind === 'submenu'))
if (missing.length || stale.length || unbuilt.length || orphan.length || galleryMismatches.length || flatMismatches.length) {
  throw new Error(JSON.stringify({missing, stale, unbuilt, orphan, galleryMismatches, flatMismatches, sourceCounts, productCounts}, null, 2))
}
console.log(JSON.stringify({sourceDropdowns: source.size, mappedMenus: mapped.size,
  productMenus: Object.keys(menus).length, maxDepth: Math.max(...Object.values(menus).map(depth)), galleries: productCounts}))

function depth(entries) {
  return Math.max(...entries.map(entry => 1 + (entry.children ? depth(entry.children) : 0)))
}
