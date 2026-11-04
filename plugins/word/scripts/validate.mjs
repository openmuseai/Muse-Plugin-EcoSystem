import {readFile} from 'node:fs/promises'
import {createHash} from 'node:crypto'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

export const root = fileURLToPath(new URL('../', import.meta.url))
const readJson = async relative => JSON.parse(await readFile(path.join(root, relative), 'utf8'))
const idPattern = /^[a-z][a-zA-Z0-9]*(?:[.-][a-zA-Z0-9]+)*$/u
const fail = message => { throw new Error(message) }
const unique = (values, label) => {
  if (new Set(values).size !== values.length) fail(`duplicate ${label}`)
}
const safePath = value => typeof value === 'string' &&
  /^product\/[a-zA-Z0-9/_-]+\.json$/u.test(value) &&
  !value.split('/').includes('..')
const safeFontPath = value => typeof value === 'string' &&
  /^product\/fonts\/[a-zA-Z0-9/_-]+\.(?:ttf|otf|woff2)$/u.test(value) &&
  !value.split('/').includes('..')

export function validateProductData(data) {
  const {product, commands, ribbon, menus, chrome, icons, shortcuts, features, templates, fonts, extensions} = data
  if (product.profile !== 'openmuse-word-product/1' || product.id !== 'io.openmuse/word' ||
      !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/u.test(product.version) || product.requires.wordApiMajor !== 1 ||
      product.requires.editorSurfaceMajor !== 2) fail('invalid product identity or API version')
  for (const entry of Object.values(product.resources).flat()) {
    if (!safePath(entry)) fail(`unsafe resource path: ${entry}`)
  }
  if (features.profile !== 'openmuse-word-features/1' || !Array.isArray(features.features)) fail('invalid features')
  const featureIds = features.features.map(f => f.id)
  unique(featureIds, 'feature id')
  for (const feature of features.features) {
    if (!idPattern.test(feature.id) || typeof feature.defaultEnabled !== 'boolean' ||
        !Array.isArray(feature.requires) || feature.requires.some(x => !idPattern.test(x))) fail(`invalid feature ${feature.id}`)
  }
  if (commands.profile !== 'openmuse-word-commands/1' || !Array.isArray(commands.commands)) fail('invalid commands')
  const commandIds = commands.commands.map(c => c.id)
  unique(commandIds, 'command id')
  for (const command of commands.commands) {
    if (!idPattern.test(command.id) || !featureIds.includes(command.feature) ||
        !['host', 'core', 'editor', 'extension'].includes(command.target) ||
        !idPattern.test(command.operation) ||
        !['read', 'write', 'edit', 'view'].includes(command.effect)) fail(`invalid command ${command.id}`)
  }
  if (menus?.profile !== 'openmuse-word-menus/1' || !menus.menus ||
      typeof menus.menus !== 'object' || Array.isArray(menus.menus)) fail('invalid menus')
  const menuIds = Object.keys(menus.menus)
  if (menuIds.length > 100) fail('too many menus')
  const coverFields = new Set(['text', 'bold', 'italic', 'color', 'sizeHalfPoints',
    'align', 'spaceBefore', 'spaceAfter', 'shadingFill', 'borders', 'indentLeft', 'indentRight'])
  const coverSpaceFields = ['spaceBefore', 'spaceAfter', 'indentLeft', 'indentRight']
  const validCoverParas = value => Array.isArray(value) && value.length >= 2 && value.length <= 8 &&
    value.every(para => para && typeof para === 'object' && !Array.isArray(para) &&
      Object.keys(para).every(key => coverFields.has(key)) &&
      (para.text === undefined || (typeof para.text === 'string' && para.text.length <= 80 &&
        !/[\u0000-\u001f\u007f]/u.test(para.text))) &&
      (para.bold === undefined || para.bold === true) &&
      (para.italic === undefined || para.italic === true) &&
      (para.color === undefined || /^[0-9a-f]{6}$/iu.test(para.color)) &&
      (para.shadingFill === undefined || /^[0-9a-f]{6}$/iu.test(para.shadingFill)) &&
      (para.sizeHalfPoints === undefined || (Number.isInteger(para.sizeHalfPoints) &&
        para.sizeHalfPoints >= 6 && para.sizeHalfPoints <= 160)) &&
      (para.align === undefined || ['left', 'center', 'right'].includes(para.align)) &&
      (para.borders === undefined || /^[tblr]{1,4}$/u.test(para.borders)) &&
      coverSpaceFields.every(key => para[key] === undefined ||
        (Number.isInteger(para[key]) && para[key] >= 0 && para[key] <= 10000)))
  const validWordArtPreview = value => value && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).every(key => ['fill', 'bold', 'italic', 'outline'].includes(key)) &&
    /^#[0-9a-f]{6}$/iu.test(value.fill) && typeof value.bold === 'boolean' &&
    typeof value.italic === 'boolean' &&
    (value.outline === undefined || (value.outline && typeof value.outline === 'object' &&
      !Array.isArray(value.outline) && Object.keys(value.outline).length === 2 &&
      Object.keys(value.outline).every(key => ['color', 'widthEmu'].includes(key)) &&
      /^#[0-9a-f]{6}$/iu.test(value.outline.color) &&
      [12700, 19050].includes(value.outline.widthEmu)))
  const validStyleInfo = value => value && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).every(key => ['styleId', 'name', 'type', 'isDefault', 'qFormat',
      'semiHidden', 'unhideWhenUsed', 'linkedCharShell', 'uiPriority', 'fontFamily',
      'sizeHalfPoints', 'color', 'bold', 'italic', 'underline', 'strike', 'caps'].includes(key)) &&
    typeof value.styleId === 'string' && /^[A-Za-z0-9_-]{1,80}$/u.test(value.styleId) &&
    typeof value.name === 'string' && value.name.length > 0 && value.name.length <= 80 &&
    ['paragraph', 'character'].includes(value.type) &&
    ['isDefault', 'qFormat', 'semiHidden', 'unhideWhenUsed', 'linkedCharShell',
      'bold', 'italic', 'underline', 'strike'].every(key => value[key] === undefined ||
        typeof value[key] === 'boolean') &&
    (value.uiPriority === undefined || (Number.isInteger(value.uiPriority) &&
      value.uiPriority >= 0 && value.uiPriority <= 100)) &&
    (value.sizeHalfPoints === undefined || (Number.isInteger(value.sizeHalfPoints) &&
      value.sizeHalfPoints >= 10 && value.sizeHalfPoints <= 160)) &&
    (value.color === undefined || /^(auto|#?[0-9a-f]{6})$/iu.test(value.color)) &&
    (value.fontFamily === undefined || (typeof value.fontFamily === 'string' &&
      value.fontFamily.length <= 80 && !/[\u0000-\u001f\u007f]/u.test(value.fontFamily))) &&
    (value.caps === undefined || ['small', 'all'].includes(value.caps))
  let nodeCount = 0
  const validateMenuNodes = (nodes, path, depth, nodeIds) => {
    if (!Array.isArray(nodes) || nodes.length === 0 || depth > 4) fail(`invalid menu ${path}`)
    for (const node of nodes) {
      if (++nodeCount > 2000 || !idPattern.test(node.id) || nodeIds.has(node.id) ||
          !['action', 'separator', 'heading', 'submenu', 'grid'].includes(node.kind ?? 'action') ||
          (node.kind !== 'separator' && (typeof node.label !== 'string' || !node.label)) ||
          (node.shortcut !== undefined && (typeof node.shortcut !== 'string' || node.shortcut.length > 32)) ||
          (node.swatch !== undefined && !/^#[0-9a-f]{6}$/iu.test(node.swatch)) ||
          (node.previewPath !== undefined && (typeof node.previewPath !== 'string' ||
            node.previewPath.length > 5000 || !/^[MLCQZ0-9.\-\s]+$/u.test(node.previewPath))) ||
          (node.previewText !== undefined && (typeof node.previewText !== 'string' ||
            node.previewText.length > 180 || /[\u0000-\u001f\u007f]/u.test(node.previewText))) ||
          (node.previewParas !== undefined &&
            (!/^insert\.cover\.[a-z]+$/u.test(node.id) || !validCoverParas(node.previewParas))) ||
          (node.previewWordArt !== undefined &&
            (!/^insert\.wordArt\.[a-z-]+$/u.test(node.id) || !validWordArtPreview(node.previewWordArt))) ||
          (node.styleInfo !== undefined &&
            (!/^home\.styles\.cell\.[1-4]$/u.test(node.id) || !validStyleInfo(node.styleInfo))) ||
          (node.presentation !== undefined && (node.kind !== 'grid' ||
            !['generic', 'colorPalette', 'highlightPalette', 'tablePicker', 'styleGallery',
              'cardGallery', 'wordArtGallery', 'symbolGallery', 'shapeGallery', 'positionPicker',
              'bulletGallery', 'numberGallery', 'multilevelGallery', 'listLevels',
              'dropCapGallery', 'equationGallery'].includes(node.presentation))) ||
          (node.command !== undefined && !commandIds.includes(node.command))) fail(`invalid menu node ${path}`)
      nodeIds.add(node.id)
      if (node.kind === 'submenu' || node.kind === 'grid') {
        if (node.command !== undefined) fail(`submenu cannot dispatch ${node.id}`)
        if (node.kind === 'grid' && (!Number.isInteger(node.columns) || node.columns < 1 ||
            node.columns > 12 || node.children.length > 100 ||
            node.children.some(child => child.kind && child.kind !== 'action'))) fail(`invalid menu grid ${node.id}`)
        if (node.kind === 'grid' && (
          (node.presentation === 'tablePicker' && (node.columns !== 10 || node.children.length !== 80)) ||
          (node.presentation === 'highlightPalette' && (node.columns !== 5 || node.children.length !== 15)) ||
          (node.presentation === 'colorPalette' && (node.columns !== 10 || ![10, 60].includes(node.children.length))) ||
          (node.presentation === 'symbolGallery' && node.columns !== 10) ||
          (node.presentation === 'wordArtGallery' && (node.columns !== 4 || node.children.length !== 12)) ||
          (node.presentation === 'wordArtGallery' && node.children.some(child =>
            !validWordArtPreview(child.previewWordArt) || child.previewWordArt.fill !== child.swatch)) ||
          (node.presentation === 'cardGallery' && (node.columns !== 4 || node.children.length !== 12 ||
            node.children.some(child => !validCoverParas(child.previewParas)))) ||
          (node.presentation === 'styleGallery' && (node.id !== 'home.styles.gallery' ||
            node.columns !== 5 || node.children.length !== 4 ||
            node.children.some(child => !validStyleInfo(child.styleInfo)))) ||
          (node.presentation === 'shapeGallery' && node.columns !== 8) ||
          (node.presentation === 'shapeGallery' && node.children.some(child => !child.previewPath)) ||
          (node.presentation === 'positionPicker' && (node.columns !== 3 || node.children.length !== 9 ||
            node.children.some(child => !/^position\.(top|center|bottom)\.[123]$/u.test(child.id)))) ||
          (node.presentation === 'bulletGallery' && (node.columns !== 3 || node.children.length !== 7)) ||
          (node.presentation === 'numberGallery' && (node.columns !== 3 || node.children.length !== 9)) ||
          (node.presentation === 'multilevelGallery' && (node.columns !== 3 || node.children.length !== 8)) ||
          (node.presentation === 'listLevels' && (node.columns !== 9 || node.children.length !== 9)) ||
          (node.presentation === 'dropCapGallery' && (node.columns !== 3 || node.children.length !== 3 ||
            node.children.some(child => !child.previewText))) ||
          (node.presentation === 'equationGallery' && (node.columns !== 1 || node.children.length !== 8 ||
            node.children.some(child => !child.previewText))) ||
          (['colorPalette', 'highlightPalette'].includes(node.presentation) &&
            node.children.some(child => !child.swatch)))) fail(`invalid menu presentation ${node.id}`)
        validateMenuNodes(node.children, `${path}.${node.id}`, depth + 1, nodeIds)
      } else if (node.children !== undefined ||
          (node.kind !== undefined && node.kind !== 'action' && node.command !== undefined)) {
        fail(`invalid menu leaf ${node.id}`)
      }
    }
  }
  for (const menuId of menuIds) {
    if (!idPattern.test(menuId)) fail(`invalid menu id ${menuId}`)
    validateMenuNodes(menus.menus[menuId], menuId, 1, new Set())
  }
  if (ribbon.profile !== 'openmuse-word-ribbon/2' || !Array.isArray(ribbon.tabs)) fail('invalid ribbon')
  const referencedMenuIds = new Set()
  unique(ribbon.tabs.map(t => t.id), 'ribbon tab')
  if (!ribbon.tabs.some(t => t.id === ribbon.initialTab)) fail('invalid initial ribbon tab')
  for (const tab of ribbon.tabs) {
    if (!idPattern.test(tab.id) || typeof tab.label !== 'string' || !Array.isArray(tab.groups) ||
        (tab.menu !== undefined && !menuIds.includes(tab.menu)) ||
        (tab.context !== undefined && !['table', 'picture', 'shape', 'headerFooter'].includes(tab.context))) fail(`invalid ribbon tab ${tab.id}`)
    if (tab.menu) referencedMenuIds.add(tab.menu)
    unique(tab.groups.map(g => g.id), `group in ${tab.id}`)
    for (const group of tab.groups) {
      if (!idPattern.test(group.id) || typeof group.label !== 'string' ||
          !['large', 'clipboard', 'twoRow', 'gallery'].includes(group.layout) || !Array.isArray(group.items)) {
        fail(`invalid ribbon group ${tab.id}.${group.id}`)
      }
      if (group.gallerySource !== undefined) {
        if (tab.id !== 'home' || group.id !== 'styles' || group.layout !== 'gallery' ||
            group.gallerySource !== 'document.quickStyles') fail('invalid dynamic style gallery')
        referencedMenuIds.add('home.styles')
      }
      unique(group.commands, `commands in ${group.id}`)
      for (const id of group.commands) if (!commandIds.includes(id)) fail(`unknown ribbon command ${id}`)
      unique(group.items.map(item => item.id), `control in ${tab.id}.${group.id}`)
      for (const item of group.items) {
        if (!idPattern.test(item.id) || typeof item.label !== 'string' || !item.label ||
            !['large', 'icon', 'combo', 'style'].includes(item.kind) ||
            typeof item.icon !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(item.icon) ||
            (item.row !== undefined && ![0, 1].includes(item.row)) ||
            (item.width !== undefined && (!Number.isInteger(item.width) || item.width < 40 || item.width > 200)) ||
            (item.command !== undefined && !group.commands.includes(item.command)) ||
            (item.menu !== undefined && !menuIds.includes(item.menu))) {
          fail(`invalid ribbon control ${tab.id}.${group.id}.${item.id}`)
        }
        if (item.menu) referencedMenuIds.add(item.menu)
      }
      if (group.commands.some(id => !group.items.some(item => item.command === id))) {
        fail(`unrepresented ribbon command in ${tab.id}.${group.id}`)
      }
    }
  }
  for (const menuId of menuIds) if (!referencedMenuIds.has(menuId)) fail(`orphan menu ${menuId}`)
  if (icons?.profile !== 'openmuse-word-icons/1' || !icons.icons ||
      typeof icons.icons !== 'object' || Array.isArray(icons.icons) ||
      Object.keys(icons.icons).length > 100) fail('invalid icon atlas')
  const usedIcons = new Set([
    ...ribbon.tabs.flatMap(tab => tab.groups.flatMap(group => group.items.map(item => item.icon))),
    ...chrome.quickAccess.map(item => item.icon),
    ...chrome.status.viewModes.map(item => item.icon)
  ])
  for (const [id, svg] of Object.entries(icons.icons)) {
    if (!/^[a-z][a-z0-9_]*$/u.test(id) || !usedIcons.has(id) ||
        typeof svg !== 'string' || svg.length > 2000 ||
        !svg.startsWith('<svg ') || !svg.endsWith('</svg>') ||
        /[\u0000-\u001f\u007f]|<\?|<!|<script|<foreignObject|\bon[a-z]+\s*=|\bhref\s*=|\burl\s*\(/iu.test(svg) ||
        /<\/?(?!svg\b|path\b|rect\b|circle\b|text\b|g\b)[a-z]/iu.test(svg)) {
      fail(`invalid signed icon ${id}`)
    }
  }
  if (chrome.profile !== 'openmuse-word-chrome/1' || !chrome.metrics || !chrome.colors ||
      !Array.isArray(chrome.quickAccess) || !chrome.status || !Array.isArray(chrome.status.viewModes)) fail('invalid chrome')
  for (const [key, min, max] of [['tabRowHeight', 28, 64], ['ribbonHeight', 50, 130],
    ['compactRibbonHeight', 30, 65], ['statusHeight', 20, 48], ['pageTopInset', 0, 80],
    ['pageBottomInset', 0, 250], ['pageGap', 0, 80]]) {
    const value = chrome.metrics[key]
    if (!Number.isInteger(value) || value < min || value > max) fail(`invalid chrome metric ${key}`)
  }
  const responsive = chrome.responsive
  if (!responsive || !Number.isInteger(responsive.foldableMinWidth) ||
      !Number.isInteger(responsive.tabletMinWidth) || !Number.isInteger(responsive.desktopMinWidth) ||
      responsive.foldableMinWidth < 360 || responsive.foldableMinWidth >= responsive.tabletMinWidth ||
      responsive.tabletMinWidth >= responsive.desktopMinWidth || responsive.desktopMinWidth > 1600) {
    fail('invalid responsive breakpoints')
  }
  for (const [key, min, max] of [['tabletRibbonHeight', 45, 80], ['foldableRibbonHeight', 42, 70],
    ['mobileTabRowHeight', 40, 60], ['mobileStatusHeight', 24, 48]]) {
    const value = responsive[key]
    if (!Number.isInteger(value) || value < min || value > max) fail(`invalid responsive metric ${key}`)
  }
  for (const key of ['chrome', 'accent', 'canvas', 'status', 'border', 'text', 'muted']) {
    if (!/^#[0-9a-f]{6}$/iu.test(chrome.colors[key])) fail(`invalid chrome color ${key}`)
  }
  unique(chrome.quickAccess.map(item => item.id), 'quick access id')
  unique(chrome.status.viewModes.map(item => item.id), 'status view id')
  for (const [id, command] of [['print', 'word.view.printLayout'], ['read', 'word.view.readMode']]) {
    if (chrome.status.viewModes.find(item => item.id === id)?.command !== command) fail(`status view ${id} command missing`)
  }
  for (const item of [...chrome.quickAccess, ...chrome.status.viewModes]) {
    if (!idPattern.test(item.id) || typeof item.label !== 'string' ||
        typeof item.icon !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(item.icon) ||
        (item.kind !== undefined && !['icon', 'toggle'].includes(item.kind)) ||
        (item.command !== undefined && !commandIds.includes(item.command))) fail(`invalid chrome item ${item.id}`)
  }
  for (const key of ['page', 'wordCount', 'selectedWordCount', 'revision', 'ready']) {
    if (typeof chrome.status[key] !== 'string') fail(`invalid status label ${key}`)
  }
  if (typeof chrome.status.readExit !== 'string' || !chrome.status.readExit.trim()) fail('invalid read mode exit label')
  const statistics = chrome.status.statistics
  const statisticIds = ['pages', 'words', 'asianChars', 'nonAsianWords',
    'charsNoSpace', 'charsWithSpace', 'paragraphs', 'lines']
  if (!statistics || typeof statistics.title !== 'string' || typeof statistics.close !== 'string' ||
      !Array.isArray(statistics.rows) || statistics.rows.length !== statisticIds.length ||
      statistics.rows.some((row, i) => row.id !== statisticIds[i] ||
        typeof row.label !== 'string' || row.label.length < 1 || row.label.length > 40)) {
    fail('invalid Word statistics dialog')
  }
  const goTo = chrome.status.goTo
  const goToKeys = ['find', 'replace', 'title', 'page', 'numberHint',
    'relativeHint', 'notFound', 'previous', 'next', 'close']
  if (!goTo || goToKeys.some(key => typeof goTo[key] !== 'string' ||
      goTo[key].length < 1 || goTo[key].length > 80)) fail('invalid Word Go To panel')
  const zoom = chrome.status.zoom
  if (!zoom || !Number.isInteger(zoom.minPercent) || !Number.isInteger(zoom.maxPercent) ||
      !Number.isInteger(zoom.stepPercent) || zoom.minPercent < 10 || zoom.maxPercent > 500 ||
      zoom.maxPercent <= zoom.minPercent || zoom.stepPercent < 1 || zoom.stepPercent > 100 ||
      !Array.isArray(zoom.presets) || zoom.presets.length !== 3 ||
      zoom.presets.some(value => !Number.isInteger(value) || value < zoom.minPercent || value > zoom.maxPercent) ||
      new Set(zoom.presets).size !== zoom.presets.length) fail('invalid status zoom policy')
  if (shortcuts.profile !== 'openmuse-word-shortcuts/1' || !Array.isArray(shortcuts.bindings)) fail('invalid shortcuts')
  unique(shortcuts.bindings.map(s => `${s.platform}:${s.keys}`), 'shortcut')
  for (const binding of shortcuts.bindings) {
    if (!['desktop', 'web'].includes(binding.platform) || !commandIds.includes(binding.command) ||
        !/^Primary\+(?:Shift\+)?[A-Z]$/u.test(binding.keys)) fail(`invalid shortcut ${binding.keys}`)
  }
  unique(templates.map(t => t.id), 'template id')
  for (const template of templates) {
    if (template.profile !== 'openmuse-word-template/1' || !idPattern.test(template.id) ||
        !Array.isArray(template.blocks) || template.blocks.length > 100 ||
        template.blocks.some(b => b.kind !== 'paragraph' || !['title', 'heading1', 'body'].includes(b.style) ||
          typeof b.text !== 'string' || b.text.length > 10000)) fail(`invalid template ${template.id}`)
  }
  if (fonts.profile !== 'openmuse-word-fonts/1' || !Array.isArray(fonts.bundled) ||
      !fonts.fallbacks || typeof fonts.fallbacks !== 'object') fail('invalid font catalog')
  for (const font of fonts.bundled) {
    if (!safeFontPath(font.file) || !/^[a-f0-9]{64}$/u.test(font.sha256) || !font.license) fail('invalid bundled font')
  }
  unique(extensions.map(e => e.id), 'extension id')
  for (const extension of extensions) {
    if (extension.profile !== 'openmuse-word-extension/1' || extension.version !== 1 ||
        !commandIds.includes(extension.command) || extension.invocation !== 'explicit' ||
        extension.offline !== true || extension.operation !== 'extension.word-count.v1' ||
        extension.desktopMcpTool !== 'word_count_text' ||
        extension.portableModule !== 'extensions/word_count.mjs') fail(`invalid extension ${extension.id}`)
    const command = commands.commands.find(c => c.id === extension.command)
    if (command.target !== 'extension' || command.operation !== extension.operation) fail(`extension mismatch ${extension.id}`)
  }
  return {id: product.id, version: product.version, commands: commands.commands.length,
    templates: templates.length, extensions: extensions.length}
}

export async function validateSource() {
  const product = await readJson('product/product.json')
  const resourcePaths = Object.values(product.resources).flat()
  unique(resourcePaths, 'resource path')
  for (const resource of resourcePaths) if (!safePath(resource)) fail(`unsafe resource path: ${resource}`)
  const [commands, ribbon, menus, chrome, icons, shortcuts, features, fonts, templates, extensions] = await Promise.all([
    readJson(product.resources.commands), readJson(product.resources.ribbon),
    readJson(product.resources.menus),
    readJson(product.resources.chrome),
    readJson(product.resources.icons),
    readJson(product.resources.shortcuts), readJson(product.resources.features),
    readJson(product.resources.fonts), Promise.all(product.resources.templates.map(readJson)),
    Promise.all(product.resources.extensions.map(readJson))
  ])
  const result = validateProductData({product, commands, ribbon, menus, chrome, icons, shortcuts, features, fonts, templates, extensions})
  for (const font of fonts.bundled) {
    const bytes = await readFile(path.join(root, font.file))
    if (bytes.length > 32 * 1024 * 1024 || createHash('sha256').update(bytes).digest('hex') !== font.sha256) {
      fail(`font digest mismatch: ${font.file}`)
    }
  }
  return result
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(await validateSource()))
}
