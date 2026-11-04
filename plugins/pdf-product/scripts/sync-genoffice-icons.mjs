import {readFile, writeFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

// Development-time import only. The signed package contains the generated
// artwork and never needs the GenOffice repository at runtime or build time.
const root = fileURLToPath(new URL('../', import.meta.url))
const upstream = path.resolve(root, '../genoffice-pptx/vendor/genoffice/apps/pdf/src/renderer/icons.tsx')
const source = await readFile(upstream, 'utf8')

const refs = {
  'quick.save': 'IconSave', 'quick.undo': 'IconUndo', 'quick.redo': 'IconRedo',
  'home.summary': 'IconAiSummarize', 'home.keypoints': 'IconAiKeyPoints',
  'home.highlight': 'IconHighlight', 'home.underline': 'IconUnderline',
  'home.strike': 'IconStrike', 'home.editText': 'IconEditText',
  'home.insertText': 'IconFormText', 'home.convert': 'IconConvertPdf',
  'home.fitWidth': 'IconFitWidth', 'home.fitPage': 'IconFitPage',
  'home.search': 'IconSearch', 'home.print': 'IconPrint',
  'home.exportImage': 'IconExportImg', 'home.properties': 'IconProps',
  'annotate.review': 'IconAiSummarize', 'annotate.notes': 'IconAiSummarize',
  'annotate.highlight': 'IconHighlight', 'annotate.underline': 'IconUnderline',
  'annotate.strike': 'IconStrike', 'annotate.ink': 'IconInk',
  'annotate.rect': 'IconRect', 'annotate.ellipse': 'IconEllipse',
  'annotate.arrow': 'IconArrow', 'annotate.note': 'IconNote',
  'annotate.redact': 'IconRect', 'annotate.sign': 'IconSign',
  'annotate.certSign': 'IconCertSign', 'annotate.color': 'IconDrawColor',
  'edit.editText': 'IconEditText', 'edit.insertText': 'IconFormText',
  'edit.insertImage': 'IconInsertImage', 'edit.editImage': 'IconEditImage',
  'edit.watermark': 'IconWatermark',
  'page.rotateLeft': 'IconRotateL', 'page.rotateRight': 'IconRotateR',
  'page.rotateAll': 'IconRotateAll', 'page.delete': 'IconDeletePage',
  'page.extract': 'IconExtract', 'page.insertPdf': 'IconInsertPdf',
  'page.insertBlank': 'IconInsertBlank', 'page.replace': 'IconReplacePages',
  'page.crop': 'IconCropPages', 'page.size': 'IconPageSize',
  'page.reverse': 'IconReverse', 'page.splitPdf': 'IconSplitPdf',
  'page.mergePdf': 'IconMergePdf', 'page.mergePages': 'IconMergePages',
  'page.splitPages': 'IconSplitPages',
  'view.thumbs': 'IconThumbs', 'view.outline': 'IconOutline',
  'view.search': 'IconSearch',
  'view.spread': 'IconSpread', 'view.night': 'IconNight',
  'view.fitWidth': 'IconFitWidth', 'view.fitPage': 'IconFitPage',
  'fillForm.aiFill': 'IconFormAiFill', 'fillForm.addText': 'IconFormText',
  'fillForm.check': 'IconFormCheck', 'fillForm.cross': 'IconFormCross',
  'fillForm.previous': 'IconPreviousField', 'fillForm.next': 'IconNextField',
  'fillForm.sign': 'IconSign', 'fillForm.image': 'IconInsertImage',
  'fillForm.complete': 'IconCompleteForm',
  'formDesign.text': 'IconFieldText', 'formDesign.date': 'IconFieldDate',
  'formDesign.checkbox': 'IconFieldCheckbox', 'formDesign.radio': 'IconFieldRadio',
  'formDesign.choice': 'IconFieldChoice',
  'formDesign.signature': 'IconFieldSignature',
  'formDesign.keep': 'IconFieldKeep', 'formDesign.preview': 'IconFieldPreview',
  'formDesign.detect': 'IconFieldDetect', 'formDesign.arrange': 'IconFieldArrange',
  'formDesign.delete': 'IconTrash',
}

const exports = new Map()
const declaration = /export const (Icon\w+) = \(\) => \(\s*<(Icon|IconRatio|svg)\b[^>]*>([\s\S]*?)<\/\2>\s*\)/g
for (const match of source.matchAll(declaration)) exports.set(match[1], match[3])
const icons = {}
// The single-page SVG is the alternate state of the signed spread toggle.
for (const name of [...new Set([...Object.values(refs), 'IconSinglePage'])].sort()) {
  const raw = exports.get(name)
  if (!raw) throw new Error(`GenOffice icon not found: ${name}`)
  const body = raw.trim()
    .replace(/([A-Za-z]+)=\{([0-9.]+)\}/g, '$1="$2"')
    .replace(/([a-z])([A-Z])/g, (_, a, b) => `${a}-${b.toLowerCase()}`)
    .replaceAll('currentColor', '#000000')
  if (/[{}]/.test(body) || /<script|<image|href=|onload=/i.test(body)) {
    throw new Error(`Unsupported icon markup: ${name}`)
  }
  icons[name] = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`
}
const output = {
  profile: 'openmuse-pdf-icons/1',
  upstream: 'GenOffice apps/pdf/src/renderer/icons.tsx (Apache-2.0)',
  refs,
  icons,
}
await writeFile(path.join(root, 'product/icons.json'), JSON.stringify(output, null, 2) + '\n')
console.log(`Synced ${Object.keys(icons).length} SVGs for ${Object.keys(refs).length} controls`)
