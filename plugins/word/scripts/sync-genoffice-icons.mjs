import {readFile, writeFile} from 'node:fs/promises'
import path from 'node:path'
import vm from 'node:vm'
import {transform} from 'esbuild'
import {root} from './validate.mjs'

const source = path.resolve(root, '../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/components/icons.tsx')
const output = path.join(root, 'product/icons.json')

// Bind product semantic names to the glyphs used by the corresponding Docs
// ribbon controls. Unmapped controls retain the interpreter's fallback icon.
const bindings = {
  save: 'IconSave', undo: 'IconUndo', redo: 'IconRedo',
  auto_awesome: 'IconSparkle', edit_spark: 'IconWand',
  sync: 'IconConvert', content_paste: 'IconPaste', content_cut: 'IconCut',
  content_copy: 'IconCopy', format_paint: 'IconFormatPainter',
  text_increase: 'IconGrowFont', text_decrease: 'IconShrinkFont',
  format_clear: 'IconClearFormat', format_color_text: 'IconFontColorA',
  border_color: 'IconHighlight', format_color_fill: 'IconShading',
  format_list_bulleted: 'IconBullets', format_list_numbered: 'IconNumbered',
  list: 'IconMultilevel', format_indent_decrease: 'IconIndentDec',
  format_indent_increase: 'IconIndentInc', format_line_spacing: 'IconLineSpacing',
  format_align_left: 'IconAlignLeft', format_align_center: 'IconAlignCenter',
  format_align_right: 'IconAlignRight', format_align_justify: 'IconAlignJustify',
  border_all: 'IconBorderAll', insert_page_break: 'IconPageBreak',
  table_chart: 'IconTable', image: 'IconPicture', category: 'IconShapes',
  bar_chart: 'IconChart', link: 'IconLink', crop_free: 'IconCrop',
  screen_rotation: 'IconRotateRight', view_column: 'IconColumns',
  toc: 'IconToc', note_add: 'IconFootnote', format_quote: 'IconCitation',
  spellcheck: 'IconSpellcheck', add_comment: 'IconComment',
  history: 'IconTrackChanges', menu_book: 'IconBook',
  zoom_dialog: 'IconZoom', zoom_out: 'IconZoomOut', zoom_in: 'IconZoomIn',
  zoom_100: 'IconZoom100', page_width: 'IconPageWidth',
  whole_page: 'IconWholePage', multi_page: 'IconMultiPage',
  numbers: 'IconWordCount',
  functions: 'IconEquation', open_with: 'IconPosition',
  wrap_text: 'IconWrapText', translate: 'IconTranslate',
  delete_outline: 'IconTableDelete', settings: 'IconGear',
  visibility: 'IconEye', close: 'IconClose', check: 'IconCheck',
  select_all: 'IconSelectAll', palette: 'IconTheme',
  color_lens: 'IconThemeColors', water_drop: 'IconPageColor',
  print_layout: 'IconPrintLayout', web_layout: 'IconWebLayout',
  outline_view: 'IconOutlineView', read_mode: 'IconReadMode',
  dark_mode: 'IconMoon', ruler: 'IconRuler',
  gridlines: 'IconGridlines', navigation_pane: 'IconNavPane',
  new_window: 'IconNewWindow', split_view: 'IconSplit',
  switch_windows: 'IconSwitchWindows',
}

const Fragment = Symbol('Fragment')
function h(type, props, ...children) {
  const combined = children.length === 1 ? children[0] : children
  if (typeof type === 'function') return type({...props, children: combined})
  return {type, props: props ?? {}, children: combined}
}
const tsx = await readFile(source, 'utf8')
const compiled = await transform(tsx, {
  loader: 'tsx', format: 'cjs', target: 'es2022',
  jsxFactory: 'h', jsxFragment: 'Fragment',
})
const module = {exports: {}}
vm.runInNewContext(compiled.code, {h, Fragment, module, exports: module.exports}, {
  filename: source, timeout: 2000,
})

const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('"', '&quot;')
  .replaceAll('<', '&lt;').replaceAll('>', '&gt;')
const attribute = key => key === 'viewBox' ? key : key === 'className' ? 'class' :
  key.replace(/[A-Z]/gu, letter => `-${letter.toLowerCase()}`)
function serialize(node) {
  if (node == null || node === false || node === true) return ''
  if (Array.isArray(node)) return node.map(serialize).join('')
  if (typeof node !== 'object') return escape(node)
  if (node.type === Fragment) return serialize(node.children)
  if (typeof node.type !== 'string') throw new Error('Unsupported GenOffice icon node')
  const props = Object.entries(node.props).filter(([key, value]) =>
    key !== 'children' && value != null && value !== false)
  const attrs = props.map(([key, value]) => {
    if (typeof value === 'object') throw new Error(`Unsupported icon attribute ${key}`)
    return ` ${attribute(key)}="${escape(value === 'currentColor' ? '#000000' : value)}"`
  }).join('')
  return `<${node.type}${attrs}>${serialize(node.children)}</${node.type}>`
}

const icons = {}
for (const [id, componentName] of Object.entries(bindings).sort(([a], [b]) => a.localeCompare(b))) {
  const component = module.exports[componentName]
  if (typeof component !== 'function') throw new Error(`GenOffice icon missing: ${componentName}`)
  let svg = serialize(component({size: 20}))
  if (!svg.startsWith('<svg ') || !svg.includes('viewBox=')) {
    throw new Error(`Invalid GenOffice SVG: ${componentName}`)
  }
  // The 16-unit icons pin their painted stroke to 1.5/1.25/1.1 px at the
  // actual display size. The Flutter interpreter fills this root placeholder.
  if (svg.includes('viewBox="0 0 16 16"')) {
    svg = svg.replace(/^(<svg[^>]*?) stroke-width="[^"]+"/u, '$1 stroke-width="__STROKE_WIDTH__"')
    if (!svg.includes('__STROKE_WIDTH__')) throw new Error(`Missing stroke: ${componentName}`)
  }
  icons[id] = svg
}
const json = JSON.stringify({
  profile: 'openmuse-word-icons/1',
  source: 'GenOffice Docs apps/docs/src/renderer/components/icons.tsx (Apache-2.0)',
  icons,
}, null, 2) + '\n'
if (process.argv.includes('--write')) {
  await writeFile(output, json)
  console.log(JSON.stringify({written: output, icons: Object.keys(icons).length}))
} else {
  const checked = await readFile(output, 'utf8')
  if (checked !== json) throw new Error('GenOffice icon atlas is stale; run npm run sync:icons')
  console.log(JSON.stringify({checked: output, icons: Object.keys(icons).length}))
}
