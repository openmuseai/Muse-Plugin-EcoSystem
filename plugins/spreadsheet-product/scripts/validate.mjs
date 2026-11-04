import {readFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

export const root = fileURLToPath(new URL('../', import.meta.url))
const read = async name => JSON.parse(await readFile(path.join(root, 'product', name), 'utf8'))
const assert = (condition, message) => {if (!condition) throw new Error(message)}

export async function validateSource() {
  const [product, chrome, commands, features, pkg] = await Promise.all([
    read('product.json'), read('chrome.json'), read('commands.json'),
    read('features.json'), readFile(path.join(root, 'package.json'), 'utf8').then(JSON.parse),
  ])
  assert(product.profile === 'openmuse-spreadsheet-product/1' &&
    product.id === 'io.openmuse/spreadsheet' &&
    product.version === pkg.version && /^\d+\.\d+\.\d+$/u.test(product.version) &&
    product.requires.spreadsheetAbiMajor === 1 && product.requires.surfaceMajor === 1,
  'invalid spreadsheet product identity')
  assert(chrome.profile === 'openmuse-spreadsheet-chrome/1' &&
    chrome.initialTab === 'home' && Array.isArray(chrome.tabs) && chrome.tabs.length === 11,
  'invalid spreadsheet chrome')
  assert(Array.isArray(chrome.statusStatistics) &&
    chrome.statusStatistics.map(x=>x.id).join(',') === 'AVERAGE,COUNTA,COUNT,MIN,MAX,SUM' &&
    chrome.statusStatistics.every(x=>typeof x.label === 'string' && x.label.length > 0 && typeof x.defaultEnabled === 'boolean'),
  'invalid status statistics')
  assert(Array.isArray(chrome.statusViews) && chrome.statusViews.length === 2 &&
    chrome.statusViews.map(x=>x.value).join(',') === 'normal,pageBreakPreview' &&
    chrome.statusViews.every(x=>typeof x.label === 'string' && x.label &&
      typeof x.icon === 'string' && x.icon && typeof x.command === 'string'),
  'invalid status views')
  const zoom = chrome.zoomDialog
  assert(zoom && ['title','magnification','fitSelection','custom','cancel','confirm','rangeError','zoomCommand','fitSelectionCommand'].every(key=>
    typeof zoom[key] === 'string' && zoom[key].length > 0) &&
    zoom.min === 10 && zoom.max === 400 &&
    Array.isArray(zoom.presets) && zoom.presets.join(',') === '200,100,75,50,25',
  'invalid zoom dialog')
  assert(chrome.visualActions &&
    chrome.visualActions.move === 'object.move' &&
    chrome.visualActions.resize === 'object.move' &&
    chrome.visualActions.delete === 'object.delete',
  'invalid visual action bindings')
  const goTo = chrome.goToDialog
  assert(goTo && ['title','reference','placeholder','hint','invalidReference','cancel','confirm','command'].every(key =>
    typeof goTo[key] === 'string' && goTo[key].length > 0) &&
    goTo.command === 'selection.set', 'invalid Go To dialog')
  const palette = chrome.sheetTabColorPalette
  const validRow = row => Array.isArray(row) && row.length === 10 &&
    row.every(color => typeof color === 'string' && /^[0-9A-F]{6}$/u.test(color))
  assert(palette && ['noColor','themeTitle','standardTitle','moreColors'].every(key =>
    typeof palette[key] === 'string' && palette[key].length > 0) &&
    validRow(palette.themeBase) && validRow(palette.standard) &&
    Array.isArray(palette.themeShades) && palette.themeShades.length === 5 &&
    palette.themeShades.every(validRow), 'invalid sheet tab color palette')
  assert(commands.profile === 'openmuse-spreadsheet-commands/1' && Array.isArray(commands.commands), 'invalid commands')
  assert(features.profile === 'openmuse-spreadsheet-features/1' && Array.isArray(features.features), 'invalid features')
  const ids = new Set(commands.commands.map(c => c.id))
  assert(chrome.statusViews.every(x=>ids.has(x.command)), 'missing status view commands')
  assert(chrome.statusMessages &&
    ['ready','modified','limitedObjects','limitedRows'].every(key=>
      typeof chrome.statusMessages[key] === 'string' && chrome.statusMessages[key].length > 0),
  'invalid status messages')
  assert(ids.has(zoom.zoomCommand) && ids.has(zoom.fitSelectionCommand), 'missing zoom dialog commands')
  assert(ids.has(goTo.command), 'missing Go To command')
  assert(Object.values(chrome.visualActions).every(id=>ids.has(id)), 'missing visual action commands')
  assert(ids.size === commands.commands.length, 'duplicate commands')
  const featuresById = new Set(features.features.map(f => f.id))
  for (const c of commands.commands) assert(typeof c.id === 'string' &&
    featuresById.has(c.feature) && ['host','view','engine','extension'].includes(c.target),
  `invalid command ${c.id}`)
  const tabs = chrome.tabs.map(t=>t.id)
  assert(new Set(tabs).size === 11 &&
    ['home','insert','pageLayout','formulas','data','review','view',
      'chartDesign','tableDesign','shapeFormat','pictureFormat'].every(id=>tabs.includes(id)),
  'missing GenOffice ribbon tab')
  let groups=0, controls=0
  const menuIds = new Set(Object.keys(chrome.menus))
  assert(typeof chrome.sheetTabMenu === 'string' && menuIds.has(chrome.sheetTabMenu), 'invalid sheet tab menu')
  assert(Array.isArray(chrome.quickAccess) && chrome.quickAccess.map(x=>x.id).join(',') === 'save,saveAs,undo,redo,autoSave' &&
    chrome.quickAccess.every(x=>x.label && x.icon && ids.has(x.command)), 'invalid quick access')
  const walk = (list, depth=1) => {
    assert(Array.isArray(list) && list.length > 0 && depth <= 4, 'invalid menu depth')
    for (const item of list) {
      assert(typeof item.label === 'string' && item.label.length <= 80, 'invalid menu label')
      if (item.command) assert(ids.has(item.command), `unknown menu command ${item.command}`)
      if (item.params) assert(item.command && typeof item.params === 'object' && !Array.isArray(item.params) &&
        JSON.stringify(item.params).length <= 1024, `invalid menu params ${item.label}`)
      if (item.presentation) assert(item.presentation === 'colorPalette' &&
        item.children?.length > 0, `invalid menu presentation ${item.label}`)
      if (item.children) walk(item.children, depth+1)
    }
  }
  for (const items of Object.values(chrome.menus)) walk(items)
  for (const tab of chrome.tabs) {
    assert(tab.label && Array.isArray(tab.groups), `invalid tab ${tab.id}`)
    for (const group of tab.groups) {
      groups++
      assert(group.id && group.label && Array.isArray(group.items), `invalid group ${tab.id}.${group.id}`)
      assert(group.layout, `missing layout ${tab.id}.${group.id}`)
      if (group.layout) {
        assert(Array.isArray(group.layout) && group.layout.length > 0, `invalid layout ${tab.id}.${group.id}`)
        const itemIds = group.items.map(item => item.id)
        const laidOut = []
        for (const block of group.layout) {
          assert(['large','stack','rows','grid'].includes(block.type), `invalid layout type ${tab.id}.${group.id}`)
          if (block.type === 'grid') {
            assert(Array.isArray(block.rows) && block.rows.length === 3 && block.rows.every(row => Array.isArray(row) && row.length === 3), `invalid layout grid ${tab.id}.${group.id}`)
            laidOut.push(...block.rows.flat())
          } else if (block.type === 'rows') {
            assert(Array.isArray(block.rows) && block.rows.length === 2 && block.rows.every(row => Array.isArray(row) && row.length > 0), `invalid layout rows ${tab.id}.${group.id}`)
            laidOut.push(...block.rows.flat())
          } else {
            assert(Array.isArray(block.items) && block.items.length > 0, `invalid layout items ${tab.id}.${group.id}`)
            laidOut.push(...block.items)
          }
        }
        assert(laidOut.length === itemIds.length && new Set(laidOut).size === itemIds.length && laidOut.every(id => itemIds.includes(id)), `layout does not cover controls ${tab.id}.${group.id}`)
      }
      for (const item of group.items) {
        controls++
        assert(item.id && item.label && item.icon &&
          (item.command === null || ids.has(item.command)) &&
          (!item.menu || menuIds.has(item.menu)), `invalid item ${tab.id}.${group.id}.${item.id}`)
        if (item.params) assert(item.command && typeof item.params === 'object' &&
          !Array.isArray(item.params) && JSON.stringify(item.params).length <= 1024,
        `invalid control params ${tab.id}.${group.id}.${item.id}`)
      }
    }
  }
  assert(controls >= 150 && groups >= 50 && menuIds.size >= 50, 'incomplete ribbon inventory')
  assert(typeof chrome.showRibbonGroupCaptions === 'boolean', 'invalid ribbon caption setting')
  for (const metric of ['tabHeight','ribbonHeight','compactRibbonHeight','formulaHeight','sheetTabsHeight','statusHeight','aiRailWidth','ribbonLargeWidth','ribbonLargeWideWidth','ribbonFontNameWidth','ribbonFontSizeWidth','ribbonNumberFormatWidth','statusHorizontalPadding','statusZoomSliderWidth','statusViewButtonWidth','statusViewGap','rowHeaderWidth','columnHeaderHeight','dialogBackdropBlur','dialogBackdropOpacity'])
    assert(Number.isFinite(chrome.metrics[metric]) && chrome.metrics[metric] > 0, `invalid metric ${metric}`)
  assert(chrome.metrics.dialogBackdropOpacity <= 1, 'invalid backdrop opacity')
  for (const color of ['statusBackground','statusBorder','statusZoom','statusSelectedBackground','dialogPrimary','dialogPrimaryText','dialogFocus','dialogBackdrop'])
    assert(/^#[0-9a-fA-F]{6}$/u.test(chrome.colors[color]), `invalid color ${color}`)
  return {id:product.id,version:product.version,tabs:tabs.length,groups,controls,menus:menuIds.size}
}

if (process.argv[1]?.endsWith('/validate.mjs')) console.log(JSON.stringify(await validateSource()))
