import {readFile, writeFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'
import {isPillPreset, presetPath, presetPolygon} from '../../genoffice-pptx/vendor/genoffice/packages/pptx-render/src/preset-geometry.ts'

const root = fileURLToPath(new URL('../', import.meta.url))
const file = path.join(root, 'product/menus.json')
const data = JSON.parse(await readFile(file, 'utf8'))
const round = value => Math.round(value * 100) / 100
const polygonPath = points => `M ${round(points[0])} ${round(points[1])} ${
  Array.from({length: points.length / 2 - 1}, (_, i) =>
    `L ${round(points[(i + 1) * 2])} ${round(points[(i + 1) * 2 + 1])}`).join(' ')} Z`

const rounded = (w, h, radius) =>
  `M ${round(radius)} 0 L ${round(w - radius)} 0 Q ${w} 0 ${w} ${round(radius)} ` +
  `L ${w} ${round(h - radius)} Q ${w} ${h} ${round(w - radius)} ${h} ` +
  `L ${round(radius)} ${h} Q 0 ${h} 0 ${round(h - radius)} ` +
  `L 0 ${round(radius)} Q 0 0 ${round(radius)} 0 Z`

function ellipse(w, h) {
  const cx = w / 2; const cy = h / 2; const k = 0.5522847498
  return `M 0 ${round(cy)} C 0 ${round(cy - cy * k)} ${round(cx - cx * k)} 0 ${round(cx)} 0 ` +
    `C ${round(cx + cx * k)} 0 ${w} ${round(cy - cy * k)} ${w} ${round(cy)} ` +
    `C ${w} ${round(cy + cy * k)} ${round(cx + cx * k)} ${h} ${round(cx)} ${h} ` +
    `C ${round(cx - cx * k)} ${h} 0 ${round(cy + cy * k)} 0 ${round(cy)} Z`
}

function arrowHead(x1, y1, x2, y2, length) {
  const dx = x2 - x1; const dy = y2 - y1; const hypotenuse = Math.hypot(dx, dy) || 1
  const ux = dx / hypotenuse; const uy = dy / hypotenuse
  const bx = x2 - ux * length; const by = y2 - uy * length; const wing = length * 0.6
  return `M ${round(bx - uy * wing)} ${round(by + ux * wing)} ` +
    `L ${round(x2)} ${round(y2)} L ${round(bx + uy * wing)} ${round(by - ux * wing)}`
}

function preview(preset) {
  const w = 18; const h = preset.startsWith('flowChart') ? 11.16 : 18
  if (['line', 'lineArrow', 'lineArrowDouble'].includes(preset)) {
    const segments = [`M 0 ${h} L ${w} 0`]
    if (preset !== 'line') segments.push(arrowHead(0, h, w, 0, Math.min(w, h) * 0.35))
    if (preset === 'lineArrowDouble') segments.push(arrowHead(w, 0, 0, h, Math.min(w, h) * 0.35))
    return segments.join(' ')
  }
  if (preset === 'lineBent') return `M 0 ${h} L 9 ${h} L 9 0 L 18 0`
  if (preset === 'lineCurved') return `M 0 ${h} C 10.8 ${h} 7.2 0 18 0`
  const points = presetPolygon(preset, w, h)
  if (points) return polygonPath(points)
  const pathData = presetPath(preset, w, h)
  if (pathData) return [pathData.path, pathData.fillPath, pathData.strokePath].filter(Boolean).join(' ')
  if (preset === 'roundRect' || preset === 'flowChartAlternateProcess')
    return rounded(w, h, Math.min(w, h) * 0.16667)
  if (isPillPreset(preset)) return rounded(w, h, Math.min(w, h) / 2)
  if (preset === 'ellipse') return ellipse(w, h)
  if (preset === 'rect' || preset === 'flowChartProcess')
    return `M 0 0 L ${w} 0 L ${w} ${h} L 0 ${h} Z`
  throw new Error(`SHAPE_PREVIEW_UNSUPPORTED:${preset}`)
}

const cells = data.menus['insert.shapes'].flatMap(group => group.children)
if (cells.length !== 109) throw new Error(`SHAPE_COUNT_CHANGED:${cells.length}`)
const changed = cells.filter(cell => cell.previewPath !== preview(cell.id.split('.').at(-1)))
if (process.argv.includes('--write')) {
  for (const cell of cells) cell.previewPath = preview(cell.id.split('.').at(-1))
  await writeFile(file, `${JSON.stringify(data, null, 2)}\n`)
  console.log(JSON.stringify({shapes: cells.length, updated: changed.length}))
} else if (changed.length) {
  throw new Error(`SHAPE_PREVIEWS_STALE:${changed.map(cell => cell.id).join(',')}`)
} else {
  console.log(JSON.stringify({shapes: cells.length, previews: 'current'}))
}
