import {readFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

export const root = fileURLToPath(new URL('../', import.meta.url))
const read = async file => JSON.parse(await readFile(path.join(root, 'product', file), 'utf8'))
const assert = (ok, message) => { if (!ok) throw new Error(message) }

export async function validateSource() {
  const [product, chrome, icons, commands, features, packageJson] = await Promise.all([
    read('product.json'), read('chrome.json'), read('icons.json'),
    read('commands.json'), read('features.json'),
    readFile(path.join(root, 'package.json'), 'utf8').then(JSON.parse)
  ])
  assert(product.profile === 'openmuse-pdf-product/1' && product.id === 'io.openmuse/pdf' &&
    product.requires.pdfAbiMajor === 6 && product.requires.surfaceMajor === 1 &&
    /^\d+\.\d+\.\d+$/u.test(product.version) &&
    product.version === packageJson.version, 'invalid PDF product identity')
  assert(chrome.profile === 'openmuse-pdf-chrome/1' && chrome.initialTab === 'home' &&
    Array.isArray(chrome.tabs) && chrome.tabs.length === 7, 'invalid PDF chrome')
  assert(icons.profile === 'openmuse-pdf-icons/1' &&
    icons.refs && typeof icons.refs === 'object' &&
    icons.icons && typeof icons.icons === 'object', 'invalid PDF icon resource')
  assert(commands.profile === 'openmuse-pdf-commands/1' && Array.isArray(commands.commands), 'invalid commands')
  assert(features.profile === 'openmuse-pdf-features/1' && Array.isArray(features.features), 'invalid features')
  const featureIds = new Set(features.features.map(f => f.id))
  const commandIds = new Set(commands.commands.map(c => c.id))
  assert(featureIds.size === features.features.length && commandIds.size === commands.commands.length,
    'duplicate feature or command')
  for (const c of commands.commands) {
    assert(/^pdf\.[A-Za-z0-9.]+$/u.test(c.id) && featureIds.has(c.feature) &&
      ['host', 'core', 'editor', 'extension'].includes(c.target) &&
      ['read', 'write', 'edit', 'view'].includes(c.effect), `invalid command ${c.id}`)
  }
  const tabs = chrome.tabs.map(t => t.id)
  assert(new Set(tabs).size === tabs.length &&
    ['home', 'annotate', 'edit', 'page', 'view', 'fillForm', 'formDesign'].every(t => tabs.includes(t)),
  'missing GenOffice tab')
  const menuIds = new Set(Object.keys(chrome.menus))
  assert(menuIds.has(chrome.sidebarContextMenu), 'invalid PDF sidebar context menu')
  assert(menuIds.size === 3 && ['convert', 'arrange', 'thumbnail'].every(id => menuIds.has(id)) &&
    chrome.menus.convert.length === 5 && chrome.menus.arrange.length === 11 &&
    chrome.menus.arrange.every(item => !item.children),
  'GenOffice PDF ribbon menu structure changed')
  assert(chrome.presentations?.ai === 'panelToggle' &&
    chrome.presentations?.highlight === 'splitColor' &&
    chrome.presentations?.color === 'colorPalette' &&
    chrome.presentations?.arrange === 'selectionRequired' &&
    chrome.presentations?.spread === 'pageArrangementToggle' &&
    Object.keys(chrome.presentations).length === 5, 'invalid PDF presentation map')
  const arrangement = chrome.pageArrangement
  const viewItems = chrome.tabs.find(tab => tab.id === 'view')?.groups
    .find(group => group.id === 'navigation')?.items ?? []
  assert(arrangement?.profile === 'openmuse-pdf-page-arrangement/1' &&
    arrangement.command === 'pdf.view.toggleSpread' &&
    Object.keys(arrangement).length === 4 &&
    arrangement.singleButton?.label === '双页' &&
    arrangement.singleButton?.icon === 'IconSpread' &&
    arrangement.spreadButton?.label === '单页' &&
    arrangement.spreadButton?.icon === 'IconSinglePage' &&
    Object.keys(arrangement.singleButton).length === 2 &&
    Object.keys(arrangement.spreadButton).length === 2 &&
    Object.hasOwn(icons.icons, arrangement.singleButton.icon) &&
    Object.hasOwn(icons.icons, arrangement.spreadButton.icon) &&
    viewItems.filter(item => item[0] === 'spread').length === 1 &&
    viewItems.some(item => item[0] === 'spread' && item[3] === arrangement.command) &&
    !viewItems.some(item => item[0] === 'single'),
  'invalid GenOffice page arrangement toggle')
  const extractDialog = chrome.dialogs?.extractRange
  const splitDialog = chrome.dialogs?.splitPdf
  assert(extractDialog?.command === 'pdf.page.extract' &&
    ['title', 'hint', 'cancel', 'confirm'].every(key =>
      typeof extractDialog[key] === 'string' && extractDialog[key].length > 0 &&
      extractDialog[key].length <= 100) &&
    extractDialog.hint.includes('{total}') &&
    extractDialog.desktopDestination === 'generatedDirectory' &&
    extractDialog.desktopOpenResult === 'newDocumentTab' &&
    extractDialog.mobileDestination === 'savePicker' &&
    extractDialog.singleNamePattern === '{base}-p{first}.pdf' &&
    extractDialog.rangeNamePattern === '{base}-p{first}-{last}.pdf' &&
    splitDialog?.command === 'pdf.page.split' &&
    ['title', 'hint', 'cancel', 'confirm'].every(key =>
      typeof splitDialog[key] === 'string' && splitDialog[key].length > 0 &&
      splitDialog[key].length <= 100) &&
    splitDialog.hint.includes('{total}') &&
    splitDialog.destinationMode === 'directory' &&
    splitDialog.fileNamePattern === '{base}-{index}.pdf' &&
    Object.keys(chrome.dialogs).length === 2,
  'invalid GenOffice page dialog')
  const searchBar = chrome.searchBar
  assert(searchBar?.command === 'pdf.search.open' &&
    ['placeholder', 'previous', 'next', 'close', 'noResults', 'searching'].every(key =>
      typeof searchBar[key] === 'string' && searchBar[key].length > 0 &&
      searchBar[key].length <= 40) &&
    searchBar.inputWidth === 180 && Object.keys(searchBar).length === 8,
  'invalid GenOffice PDF search bar')
  const keyboardShortcuts = chrome.keyboardShortcuts
  const expectedShortcuts = {
    'primary+s': 'pdf.file.saveCopy',
    'primary+z': 'pdf.edit.undo',
    'primary+shift+z': 'pdf.edit.redo',
    'primary+f': 'pdf.search.open',
    'primary+=': 'pdf.view.zoomIn',
    'primary+-': 'pdf.view.zoomOut',
    'primary+0': 'pdf.view.fitWidth',
  }
  assert(keyboardShortcuts &&
    Object.keys(keyboardShortcuts).length === Object.keys(expectedShortcuts).length &&
    Object.entries(expectedShortcuts).every(([key, command]) =>
      keyboardShortcuts[key] === command && commandIds.has(command)),
  'invalid GenOffice PDF keyboard shortcuts')
  const keyboardNavigation = chrome.keyboardNavigation
  const expectedDocumentNavigation = {
    PageDown: 'viewportNext', Space: 'viewportNext',
    PageUp: 'viewportPrevious', Home: 'documentStart', End: 'documentEnd',
    ArrowDown: 'lineNext', ArrowUp: 'linePrevious',
    ArrowRight: 'pageNext', ArrowLeft: 'pagePrevious',
  }
  const expectedThumbnailNavigation = {ArrowDown: 'pageNext', ArrowUp: 'pagePrevious'}
  assert(keyboardNavigation?.linePixels === 60 && keyboardNavigation.viewportInset === 40 &&
    Object.keys(keyboardNavigation).length === 4 &&
    Object.keys(keyboardNavigation.document ?? {}).length === Object.keys(expectedDocumentNavigation).length &&
    Object.entries(expectedDocumentNavigation).every(([key, action]) =>
      keyboardNavigation.document[key] === action) &&
    Object.keys(keyboardNavigation.thumbnails ?? {}).length === Object.keys(expectedThumbnailNavigation).length &&
    Object.entries(expectedThumbnailNavigation).every(([key, action]) =>
      keyboardNavigation.thumbnails[key] === action),
  'invalid GenOffice PDF keyboard navigation')
  const palette = chrome.palette
  const hex = value => typeof value === 'string' && /^#[0-9a-f]{6}$/u.test(value)
  const themeKeys = ['chrome', 'surface', 'canvas', 'status', 'statusBorder',
    'text', 'muted', 'border', 'borderStrong', 'accent', 'hover', 'saveOk', 'saveError']
  assert(chrome.themes?.default === 'light' &&
    Object.keys(chrome.themes).length === 3 &&
    ['light', 'dark'].every(mode => {
      const colors = chrome.themes[mode]
      return colors && Object.keys(colors).length === themeKeys.length &&
        themeKeys.every(key => hex(colors[key]))
    }), 'invalid PDF theme palettes')
  assert(palette?.profile === 'openmuse-pdf-palette/1' &&
    Array.isArray(palette.theme) && palette.theme.length === 10 && palette.theme.every(hex) &&
    Array.isArray(palette.shades) && palette.shades.length === 5 &&
    palette.shades.every(row => Array.isArray(row) && row.length === 10 && row.every(hex)) &&
    Array.isArray(palette.standard) && palette.standard.length === 10 &&
    palette.standard.every(hex) &&
    ['theme', 'standard', 'more'].every(key => typeof palette.labels?.[key] === 'string'),
  'invalid GenOffice PDF palette')
  for (const name of ['tabHeight', 'ribbonHeight', 'compactRibbonHeight',
    'statusHeight', 'sidebarWidth', 'aiRailWidth']) {
    assert(Number.isFinite(chrome.metrics?.[name]) && chrome.metrics[name] > 0,
      `invalid PDF metric ${name}`)
  }
  const responsiveLayout = chrome.responsiveLayout
  assert(responsiveLayout?.profile === 'openmuse-pdf-layout/1' &&
    responsiveLayout.mobileBelow === 600 &&
    responsiveLayout.compactBelow === 900 &&
    responsiveLayout.minDocumentWidth === 400 &&
    Object.keys(responsiveLayout).length === 4,
  'invalid responsive PDF shell layout')
  const menuStyleKeys = ['minWidth', 'padding', 'radius', 'offsetY', 'itemHeight',
    'itemHorizontalPadding', 'fontSize', 'elevation', 'shadowOpacity']
  const menuPresentation = chrome.menuPresentation
  assert(menuPresentation && Object.keys(menuPresentation).length === 3 &&
    ['ribbon', 'thumbnail', 'palette'].every(kind => {
      const spec = menuPresentation[kind]
      return spec && Object.keys(spec).length === menuStyleKeys.length &&
        menuStyleKeys.every(key => Number.isFinite(spec[key]) && spec[key] >= 0) &&
        spec.shadowOpacity <= 1 && spec.radius > 0 && spec.fontSize > 0
    }) &&
    menuPresentation.ribbon.minWidth === 148 &&
    menuPresentation.ribbon.itemHeight === 28 &&
    menuPresentation.thumbnail.minWidth === 170 &&
    menuPresentation.thumbnail.itemHeight === 32 &&
    menuPresentation.palette.padding === 8,
  'invalid GenOffice menu presentation')
  const sidebar = chrome.sidebar
  assert(sidebar?.minWidth === 120 && sidebar.maxWidth === 320 &&
    sidebar.maxViewportFraction === 0.4 && sidebar.rasterInset === 24 &&
    sidebar.resizerWidth === 6 && sidebar.resizerOverlap === 3 &&
    sidebar.preferenceKey === 'openmuse.pdf.sidebar.width' &&
    chrome.metrics.sidebarWidth === 150 &&
    Object.keys(sidebar).length === 7,
  'invalid GenOffice PDF sidebar geometry')
  const viewport = chrome.pageViewport
  assert(viewport?.horizontalPadding === 24 &&
    viewport.verticalPadding === 16 && viewport.pageGap === 16 &&
    Object.keys(viewport).length === 4 &&
    viewport.shadow?.color === '#000000' &&
    viewport.shadow.opacity === 0.18 && viewport.shadow.blurRadius === 4 &&
    viewport.shadow.spreadRadius === 0 &&
    viewport.shadow.offsetX === 0 && viewport.shadow.offsetY === 1 &&
    Object.keys(viewport.shadow).length === 6,
  'invalid GenOffice PDF page viewport')
  const aiDock = chrome.aiDock
  assert(aiDock?.defaultWidth === 360 && aiDock.minWidth === 280 &&
    aiDock.maxWidth === 720 && aiDock.maxViewportFraction === 0.6 &&
    aiDock.railWidth === chrome.metrics.aiRailWidth &&
    aiDock.resizerWidth === 6 && aiDock.transitionMs === 180 &&
    aiDock.widthPreferenceKey === 'openmuse.pdf.ai.width' &&
    aiDock.openPreferenceKey === 'openmuse.pdf.ai.open' &&
    aiDock.initiallyOpen === true &&
    ['title', 'openLabel', 'collapseLabel', 'emptyTitle', 'emptyBody',
      'unavailable', 'summaryLabel', 'keyPointsLabel', 'promptPlaceholder']
      .every(key => typeof aiDock[key] === 'string' && aiDock[key].length > 0 &&
        aiDock[key].length <= 80) &&
    Object.keys(aiDock).length === 19,
  'invalid GenOffice PDF AI dock geometry')
  const status = chrome.statusBar
  assert(status && ['pageLabel', 'zoomOut', 'zoomIn', 'thumbnails'].every(
    key => typeof status[key] === 'string' && status[key].length > 0) &&
    status.pageLabel.includes('{current}') && status.pageLabel.includes('{total}') &&
    status.minZoom === 0.1 && status.maxZoom === 8 &&
    status.sliderStep === 0.05 && status.sliderWidth === 110 &&
    status.minSliderColumnWidth === 380 &&
    Array.isArray(status.zoomSteps) && status.zoomSteps.length === 18 &&
    status.zoomSteps[0] === status.minZoom &&
    status.zoomSteps.at(-1) === status.maxZoom &&
    status.zoomSteps.every((value, index) =>
      Number.isFinite(value) && (index === 0 || value > status.zoomSteps[index - 1])),
  'invalid GenOffice PDF status bar')
  const ribbonState = chrome.ribbonState
  assert(ribbonState &&
    ['unsaved', 'savingCopy', 'copySaved', 'copyFailed', 'readOnly'].every(
      key => typeof ribbonState[key] === 'string' && ribbonState[key].length > 0 &&
        ribbonState[key].length <= 40) &&
    ribbonState.fontSize === 12 && ribbonState.feedbackMs === 3000 &&
    Object.keys(ribbonState).length === 7,
  'invalid GenOffice PDF ribbon state')
  let controlCount = 0
  const controls = new Set(chrome.quickAccess.map(c => `quick.${c.id}`))
  for (const tab of chrome.tabs) {
    assert(typeof tab.label === 'string' && Array.isArray(tab.groups), `invalid tab ${tab.id}`)
    for (const group of tab.groups) {
      assert(typeof group.id === 'string' && Array.isArray(group.items), `invalid group ${group.id}`)
      if (group.layout) assert(group.layout === 'pageZoom', `invalid group layout ${group.layout}`)
      for (const item of group.items) {
        assert(Array.isArray(item) && item.length >= 4 && item.length <= 5 &&
          item.every((v, i) => i === 3 ? v === null || commandIds.has(v) : typeof v === 'string'),
        `invalid item in ${tab.id}.${group.id}`)
        if (item[4]) assert(menuIds.has(item[4]), `unknown menu ${item[4]}`)
        controls.add(`${tab.id}.${item[0]}`)
        controlCount++
      }
    }
  }
  for (const [control, icon] of Object.entries(icons.refs)) {
    assert(controls.has(control) && typeof icon === 'string' &&
      Object.hasOwn(icons.icons, icon), `invalid PDF icon reference ${control}`)
  }
  for (const [name, svg] of Object.entries(icons.icons)) {
    assert(/^Icon[A-Za-z0-9]+$/u.test(name) && typeof svg === 'string' &&
      svg.startsWith('<svg ') && svg.endsWith('</svg>') && svg.length < 8000 &&
      !/<(?:script|image|foreignObject)\b|(?:href|onload|onerror)=/iu.test(svg),
    `unsafe PDF icon ${name}`)
  }
  const walk = (items, depth = 1) => {
    assert(Array.isArray(items) && items.length && depth <= 4, 'invalid PDF menu depth')
    for (const item of items) {
      assert(typeof item.label === 'string' && item.label.length <= 80, 'invalid menu item')
      if (item.command) assert(commandIds.has(item.command), `unknown menu command ${item.command}`)
      if (item.uiAction) assert(item.uiAction === 'highlightColor' &&
        /^#[0-9a-fA-F]{6}$/u.test(item.color) && !item.command && !item.children,
      `invalid PDF menu UI action ${item.uiAction}`)
      if (item.children) walk(item.children, depth + 1)
    }
  }
  for (const items of Object.values(chrome.menus)) walk(items)
  for (const file of Object.values(product.resources)) {
    assert(/^product\/[a-z-]+\.json$/u.test(file), `unsafe resource ${file}`)
  }
  return {id: product.id, version: product.version, tabs: tabs.length, controls: controlCount}
}

if (process.argv[1]?.endsWith('/validate.mjs')) console.log(JSON.stringify(await validateSource()))
