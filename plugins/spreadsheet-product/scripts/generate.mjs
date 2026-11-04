import {writeFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))
const out = (name, value) => writeFile(path.join(root, 'product', name), JSON.stringify(value, null, 2) + '\n')
const group = (id, label, rows) => ({id, label, items: rows.trim().split('\n').map(line => {
  const [id, label, icon, command, menu, params] = line.split('|')
  return {id, label, icon, command: command || null, ...(menu ? {menu} : {}),
    ...(params ? {params:JSON.parse(params)} : {})}
})})
const tab = (id, label, groups, when) => ({id, label, groups, ...(when ? {when} : {})})

// The signed product owns ribbon composition; the Host surface only knows
// generic large/stack/rows presentation primitives.
const large = (...items) => ({type:'large',items})
const stack = (...items) => ({type:'stack',items})
const rows = (top, bottom) => ({type:'rows',rows:[top,bottom]})
const grid = (...rows) => ({type:'grid',rows})
// Source: GenOffice apps/sheets/src/renderer/ExcelShell.tsx Ribbon branches.
// These are product data, so tabs/groups can change without a Host release.
const ribbonLayouts = {
  home: {
    ai: [large('assistant','check','analyze')],
    clipboard: [large('paste','pasteSpecial'),stack('cut','copy','painter')],
    font: [rows(['fontName','fontSize','grow','shrink'],['bold','italic','underline','strike','super','sub','borders','fill','fontColor'])],
    alignment: [rows(['top','middle','bottom','orientation'],['left','center','right','wrap','merge'])],
    number: [rows(['numberFormat'],['currency','percent','comma','decMore','decLess'])],
    styles: [stack('conditional','formatTable','cellStyle')],
    cells: [stack('insertCells','deleteCells','formatCells')],
    editing: [large('sum'),rows(['fillDown','clear'],['sort','find'])],
  },
  insert: {
    tables: [large('pivot','pivotEdit','table')],
    illustrations: [large('picture'),stack('shape','icons','screenshot')],
    checkbox: [large('checkbox')],
    charts: [large('recommended'),grid(['column','bar','line'],['area','pie','scatter'],['radar','doughnut','combo']),large('pivotChart')],
    sparklines: [large('sparkline')], filters: [stack('slicer','timeline')],
    links: [large('link')], comments: [large('comment')],
    text: [large('textBox','headerFooter')], symbols: [stack('equation','symbol')],
  },
  pageLayout: {
    themes: [large('theme'),stack('colors','fonts')],
    pageSetup: [large('margins','orientation','size','printArea','breaks','printTitles')],
    scale: [stack('width','height')],
    options: [stack('gridlines','printGridlines'),stack('headings','printHeadings')],
  },
  formulas: {
    library: [large('insertFunction','autoSum','recent','financial','logical','text','date','lookup','math','more')],
    names: [large('nameManager'),stack('defineName','useFormula','createNames')],
    auditing: [stack('tracePrecedents','traceDependents','removeArrows'),large('showFormulas','errorChecking','watchWindow')],
    calculation: [large('calcOptions'),stack('calcNow','calcSheet')],
  },
  data: {
    pivot: [large('pivot','refreshPivot')], getData: [stack('fromText','mergeWorkbooks','refreshAll')],
    sortFilter: [large('sort','filter'),stack('clearFilter','reapply','advanced')],
    tools: [large('textColumns','flashFill','removeDup','validation','consolidate')],
    forecast: [large('whatIf')],
    outline: [large('group','ungroup','subtotal')],
  },
  review: {
    proofing: [large('workbookStats')], language: [large('translate')],
    comments: [large('newComment','deleteComment'),stack('previousComment','nextComment','showComments')],
    notes: [large('notes')],
    protection: [large('protectSheet','protectBook','editRanges')],
  },
  view: {
    views: [large('normal','pageBreak')], show: [stack('gridlines','formulaBar','headings'),stack('rightToLeft','crossHighlight')],
    zoom: [large('zoom','actual','selection')],
    window: [large('freeze')],
  },
  chartDesign: {
    layout: [large('elements','quickLayout','colors')], type: [large('chartType')],
    data: [large('switch','select')], actions: [large('delete')],
  },
  tableDesign: {
    properties: [stack('name','resize')], tools: [large('summarize','removeDup')],
    options: [stack('header','total','banded')], styles: [large('style')],
  },
  shapeFormat: {
    styles: [large('fill','line')], arrange: [stack('front','back','align')],
    size: [stack('height','width')],
  },
  pictureFormat: {
    styles: [large('border','crop')], arrange: [stack('front','back','align')],
    size: [stack('height','width')],
  },
}

const tabs = [
  tab('home', '开始', [
    group('ai','AI',`assistant|Muse AI|auto_awesome||ai
check|AI 校验|fact_check||ai
analyze|AI 分析|auto_graph||ai`),
    group('clipboard','剪贴板',`paste|粘贴|content_paste|edit.paste|paste
pasteSpecial|选择性粘贴|content_paste_go|edit.pasteSpecial|pasteSpecial
cut|剪切|content_cut|edit.cut
copy|复制|content_copy|edit.copy
painter|格式刷|format_paint|edit.formatPainter`),
    group('font','字体',`fontName|字体|font_download|home.fontName|fonts
fontSize|字号|format_size|home.fontSize|sizes
grow|增大字号|text_increase|home.increaseFontSize
shrink|减小字号|text_decrease|home.decreaseFontSize
bold|加粗|format_bold|home.bold
italic|倾斜|format_italic|home.italic
underline|下划线|format_underlined|home.underline|underline
strike|删除线|strikethrough_s|home.strikethrough
super|上标|superscript|home.superscript
sub|下标|subscript|home.subscript
borders|边框|border_all|home.borders|borders
fill|填充颜色|format_color_fill|home.fillColor|colors
fontColor|字体颜色|format_color_text|home.fontColor|colors`),
    group('alignment','对齐',`top|顶端对齐|vertical_align_top|home.alignTop
middle|垂直居中|vertical_align_center|home.alignMiddle
bottom|底端对齐|vertical_align_bottom|home.alignBottom
orientation|文字方向|text_rotation_angleup|home.orientation|orientation
left|左对齐|format_align_left|home.alignLeft
center|水平居中|format_align_center|home.alignCenter
right|右对齐|format_align_right|home.alignRight
wrap|自动换行|wrap_text|home.wrapText
merge|合并后居中|call_merge|home.mergeCenter|merge`),
    group('number','数字',`numberFormat|数字格式|numbers|home.numberFormat|numberFormat
currency|会计数字格式|attach_money|home.accounting
percent|百分比|percent|home.percent
comma|千位分隔符|format_list_numbered|home.comma
decMore|增加小数位|exposure_plus_1|home.increaseDecimal
decLess|减少小数位|exposure_neg_1|home.decreaseDecimal`),
    group('styles','样式',`conditional|条件格式|rule|home.conditionalFormat|conditional
formatTable|套用表格格式|table_chart|home.formatAsTable|tableStyles
cellStyle|单元格样式|palette|home.cellStyle|cellStyles`),
    group('cells','单元格',`insertCells|插入|add_box|home.insertCells|insert
deleteCells|删除|indeterminate_check_box|home.deleteCells|delete
formatCells|格式|grid_on|home.formatCells|format`),
    group('editing','编辑',`sum|自动求和|functions|formulas.autoSum|sum
fillDown|填充|vertical_align_bottom|edit.fillDown|fill
clear|清除|backspace|edit.clearAll|clear
sort|排序和筛选|sort|data.sortAscending|sortFilter
find|查找和选择|search|edit.find|find`),
  ]),
  tab('insert','插入',[
    group('tables','表格',`pivot|数据透视表|pivot_table_chart|insert.pivotTable|pivot
pivotEdit|编辑数据透视表|pivot_table_chart|insert.pivotEdit|pivot
table|表格|table_chart|insert.table|table`),
    group('illustrations','插图',`picture|图片|image|insert.picture|picture
shape|形状|category|insert.shape|shape
icons|图标|interests|insert.icons
screenshot|屏幕截图|crop|insert.screenshot`),
    group('checkbox','复选框',`checkbox|复选框|check_box|insert.checkbox`),
    group('charts','图表',`recommended|推荐的图表|insert_chart|insert.chart|chart|{"type":"auto"}
column|柱形图|bar_chart|insert.chart||{"type":"column"}
bar|条形图|bar_chart|insert.chart||{"type":"bar"}
line|折线图|show_chart|insert.chart||{"type":"line"}
area|面积图|area_chart|insert.chart||{"type":"area"}
pie|饼图|pie_chart|insert.chart||{"type":"pie"}
scatter|散点图|scatter_plot|insert.chart||{"type":"scatter"}
radar|雷达图|radar|insert.chart||{"type":"radar"}
doughnut|圆环图|donut_large|insert.chart||{"type":"doughnut"}
combo|组合图|stacked_bar_chart|insert.chart||{"type":"combo"}
pivotChart|数据透视图|insert_chart|insert.pivotChart|pivotChart`),
    group('sparklines','迷你图',`sparkline|迷你图|multiline_chart|insert.sparkline|sparkline`),
    group('filters','筛选器',`slicer|切片器|filter_alt|insert.slicer|slicer
timeline|时间线|timeline|insert.timeline`),
    group('links','链接',`link|链接|link|insert.hyperlink|link`),
    group('comments','批注',`comment|批注|comment|review.newComment`),
    group('text','文本',`textBox|文本框|text_fields|insert.textBox
headerFooter|页眉和页脚|vertical_split|insert.headerFooter`),
    group('symbols','符号',`equation|公式|functions|insert.equation
symbol|符号|interests|insert.symbol|symbol`),
  ]),
  tab('pageLayout','页面布局',[
    group('themes','主题',`theme|主题|palette|page.theme|themes
colors|颜色|color_lens|page.colors|themeColors
fonts|字体|font_download|page.fonts|themeFonts`),
    group('pageSetup','页面设置',`margins|页边距|space_dashboard|page.margins|margins
orientation|纸张方向|screen_rotation|page.orientation|pageOrientation
size|纸张大小|crop_square|page.size|paperSizes
printArea|打印区域|select_all|page.printArea|printArea
breaks|分隔符|splitscreen|page.breaks|breaks
printTitles|打印标题|view_headline|page.printTitles|printTitles`),
    group('scale','调整为合适大小',`width|宽度|width|page.fitWidth|fitPages
height|高度|height|page.fitHeight|fitPages`),
    group('options','工作表选项',`gridlines|查看网格线|grid_on|view.gridlines
printGridlines|打印网格线|print|page.printGridlines
headings|查看标题|view_headline|view.headings
printHeadings|打印标题|print|page.printHeadings`),
  ]),
  tab('formulas','公式',[
    group('library','函数库',`insertFunction|插入函数|functions|formulas.insertFunction|functions
autoSum|自动求和|functions|formulas.autoSum|sum
recent|最近使用|history|formulas.insertFunction|functionCategories
financial|财务|attach_money|formulas.insertFunction|functionCategories
logical|逻辑|account_tree|formulas.insertFunction|functionCategories
text|文本|text_fields|formulas.insertFunction|functionCategories
date|日期和时间|today|formulas.insertFunction|functionCategories
lookup|查找与引用|search|formulas.insertFunction|functionCategories
math|数学和三角函数|functions|formulas.insertFunction|functionCategories
more|其他函数|more_horiz|formulas.insertFunction|functionCategories`),
    group('names','定义名称',`nameManager|名称管理器|list_alt|formulas.nameManager
defineName|定义名称|edit_note|formulas.defineName
useFormula|用于公式|arrow_drop_down_circle|formulas.useName|names
createNames|根据所选内容创建|add_box|formulas.createNames|createNames`),
    group('auditing','公式审核',`tracePrecedents|追踪引用单元格|subdirectory_arrow_left|formulas.tracePrecedents
traceDependents|追踪从属单元格|subdirectory_arrow_right|formulas.traceDependents
removeArrows|移去箭头|backspace|formulas.removeArrows
showFormulas|显示公式|data_object|formulas.showFormulas
errorChecking|错误检查|error_outline|formulas.errorCheck
watchWindow|监视窗口|visibility|formulas.watchWindow`),
    group('calculation','计算',`calcOptions|计算选项|calculate|formulas.calculation|calcMode
calcNow|开始计算|refresh|formulas.calculateNow
calcSheet|计算工作表|grid_on|formulas.calculateSheet`),
  ]),
  tab('data','数据',[
    group('pivot','数据透视表',`pivot|数据透视表|pivot_table_chart|insert.pivotTable|pivot
refreshPivot|刷新|refresh|data.refreshPivot`),
    group('getData','获取数据',`fromText|自文本/CSV|description|data.fromTextCsv
mergeWorkbooks|合并工作簿|join_full|data.mergeWorkbooks
refreshAll|全部刷新|refresh|data.refreshAll`),
    group('sortFilter','排序和筛选',`sort|排序|sort|data.sort|sortFilter
filter|筛选|filter_alt|data.filter|filter
clearFilter|清除|filter_alt_off|data.clearFilter
reapply|重新应用|refresh|data.reapplyFilter
advanced|高级|filter_list|data.advancedFilter`),
    group('tools','数据工具',`textColumns|分列|view_column|data.textToColumns
flashFill|快速填充|bolt|data.flashFill
removeDup|删除重复项|filter_none|data.removeDuplicates
validation|数据验证|verified_user|data.validation|validation
consolidate|合并计算|join_full|data.consolidate`),
    group('forecast','预测',`whatIf|模拟分析|insights|data.whatIf|whatIf`),
    group('outline','分级显示',`group|组合|folder|data.group|group
ungroup|取消组合|folder_off|data.ungroup|ungroup
subtotal|分类汇总|functions|data.subtotal`),
  ]),
  tab('review','审阅',[
    group('proofing','校对',`workbookStats|工作簿统计|calculate|review.workbookStats`),
    group('language','语言',`translate|翻译|translate|review.translate|translate`),
    group('comments','批注',`newComment|新建批注|add_comment|review.newComment
deleteComment|删除批注|delete|review.deleteComment
previousComment|上一条|arrow_upward|review.previousComment
nextComment|下一条|arrow_downward|review.nextComment
showComments|显示批注|comment|review.showComments|comments`),
    group('notes','注释',`notes|注释|sticky_note_2|review.newNote|notes`),
    group('protection','保护',`protectSheet|保护工作表|lock|review.protectSheet|protect
protectBook|保护工作簿|enhanced_encryption|review.protectWorkbook|protect
editRanges|允许编辑区域|edit_attributes|review.allowEditRanges`),
  ]),
  tab('view','视图',[
    group('views','工作簿视图',`normal|普通视图|grid_view|view.normal
pageBreak|分页预览|view_array|view.pageBreakPreview`),
    group('show','显示',`formulaBar|编辑栏|functions|view.formulaBar
gridlines|网格线|grid_on|view.gridlines
headings|标题|view_headline|view.headings
rightToLeft|从右向左|format_textdirection_r_to_l|view.rightToLeft
crossHighlight|十字高亮|highlight_alt|view.crossHighlight`),
    group('zoom','缩放',`zoom|缩放|zoom_in|view.zoom|zoom
actual|100%|filter_1|view.zoom100
selection|缩放到选定区域|fit_screen|view.zoomToSelection`),
    group('window','窗口',`freeze|冻结窗格|ac_unit|view.freeze|freeze`),
  ]),
  tab('chartDesign','图表设计',[
    group('layout','图表布局',`elements|添加图表元素|add_chart|chart.elements|chartElements
quickLayout|快速布局|dashboard|chart.layout|chartLayouts
colors|更改颜色|palette|chart.colors|colors`),
    group('type','更改图表类型',`chartType|更改图表类型|insert_chart|chart.changeType|chart`),
    group('data','数据',`switch|切换行/列|swap_horiz|chart.switchRowCol
select|选择数据|table_chart|chart.selectData`),
    group('actions','图表操作',`delete|删除图表|delete|chart.delete`),
  ], 'chart'),
  tab('tableDesign','表格设计',[
    group('properties','表属性',`name|表名称|drive_file_rename_outline|table.rename
resize|调整表大小|aspect_ratio|table.resize`),
    group('tools','工具',`summarize|数据透视表汇总|pivot_table_chart|table.summarize
removeDup|删除重复项|filter_none|data.removeDuplicates`),
    group('options','表格样式选项',`header|标题行|view_headline|table.header
total|汇总行|functions|table.totalRow
banded|镶边行|view_stream|table.bandedRows`),
    group('styles','表格样式',`style|表格样式|palette|table.style|tableStyles`),
  ], 'table'),
  tab('shapeFormat','形状格式',[
    group('styles','形状样式',`fill|形状填充|format_color_fill|shape.fill|colors
line|形状轮廓|border_color|shape.line|colors`),
    group('arrange','排列',`front|上移一层|flip_to_front|shape.bringForward
back|下移一层|flip_to_back|shape.sendBackward
align|对齐|align_horizontal_left|shape.align|align`),
    group('size','大小',`height|高度|height|shape.height
width|宽度|width|shape.width`),
  ], 'shape'),
  tab('pictureFormat','图片格式',[
    group('styles','图片样式',`border|图片边框|border_color|picture.border|colors
crop|裁剪|crop|picture.crop`),
    group('arrange','排列',`front|上移一层|flip_to_front|picture.bringForward
back|下移一层|flip_to_back|picture.sendBackward
align|对齐|align_horizontal_left|picture.align|align`),
    group('size','大小',`height|高度|height|picture.height
width|宽度|width|picture.width`),
  ], 'picture'),
]

for (const tab of tabs) {
  for (const group of tab.groups) group.layout = ribbonLayouts[tab.id][group.id]
}

const leaf = (label, command = null, params = null) => ({label, command, ...(params ? {params} : {})})
const submenu = (label, children, presentation) => ({label, children, ...(presentation ? {presentation} : {})})
// The signed product supplies the full Office-style palette. The surface only
// knows how to lay out named rows of swatches and dispatch sheet.tabColor.
const sheetTabColorPalette = {
  noColor:'无颜色', themeTitle:'主题颜色', standardTitle:'标准颜色', moreColors:'更多颜色…',
  themeBase:['FFFFFF','000000','E7E6E6','0E2841','156082','E97132','196B24','0F9ED5','A02B93','4EA72E'],
  themeShades:[
    ['F2F2F2','7F7F7F','D0CECE','DDEBF7','DDEBF7','FCE4D6','E2F0D9','DDEBF7','E4DFEC','E2F0D9'],
    ['D9D9D9','595959','AEAAAA','BDD7EE','9DC3E6','F8CBAD','C6E0B4','9DC3E6','D9E1F2','C6E0B4'],
    ['BFBFBF','3F3F3F','757171','8EA9DB','5B9BD5','F4B084','A9D18E','5B9BD5','B4C6E7','A9D18E'],
    ['A6A6A6','262626','3A3838','4472C4','2E75B6','C65911','70AD47','00B0F0','8064A2','70AD47'],
    ['808080','0D0D0D','171616','203864','1F4E78','843C0C','375623','0070C0','5B315E','385723'],
  ],
  standard:['C00000','FF0000','FFC000','FFFF00','92D050','00B050','00B0F0','0070C0','002060','7030A0'],
}
const menus = {
  ai: [leaf('使用 Muse AI（扩展未安装）')],
  paste: [leaf('粘贴','edit.paste'), leaf('选择性粘贴','edit.pasteSpecial')],
  pasteSpecial: [leaf('全部','edit.pasteSpecial'), leaf('仅值','edit.pasteSpecial'), leaf('仅格式','edit.pasteSpecial')],
  fonts: [leaf('Aptos'),leaf('Arial'),leaf('宋体')], sizes: [9,10,11,12,14,16,18,22,26].map(x=>leaf(String(x))),
  underline: [leaf('单下划线','home.underline'),leaf('双下划线','home.doubleUnderline')],
  borders: [leaf('所有框线','home.borders'),leaf('外侧框线','home.borders'),submenu('更多边框',[leaf('上框线','home.borders'),leaf('下框线','home.borders'),leaf('无框线','home.borders')])],
  colors: [leaf('自动'),submenu('标准颜色',[leaf('红色'),leaf('蓝色'),leaf('绿色')]),leaf('更多颜色…')],
  orientation: [leaf('逆时针角度','home.orientation'),leaf('顺时针角度','home.orientation'),leaf('垂直文字','home.orientation')],
  merge: [leaf('合并后居中','home.mergeCenter'),leaf('跨越合并','home.mergeAcross'),leaf('合并单元格','home.mergeCells'),leaf('取消合并','home.unmergeCells')],
  numberFormat: ['常规','数字','货币','会计专用','短日期','长日期','时间','百分比','分数','科学记数'].map(x=>leaf(x)),
  conditional: [submenu('突出显示单元格规则',[leaf('大于…'),leaf('小于…'),leaf('文本包含…')]),submenu('最前/最后规则',[leaf('前 10 项…'),leaf('后 10 项…')]),leaf('数据条'),leaf('色阶'),leaf('管理规则…')],
  tableStyles: [leaf('浅色'),leaf('中等'),leaf('深色')],cellStyles:[leaf('常规'),leaf('好'),leaf('坏'),leaf('标题')],
  insert:[leaf('插入单元格','home.insertCells'),leaf('插入工作表行','home.insertRows'),leaf('插入工作表列','home.insertColumns'),leaf('插入工作表','home.insertSheet')],
  delete:[leaf('删除单元格','home.deleteCells'),leaf('删除工作表行','home.deleteRows'),leaf('删除工作表列','home.deleteColumns'),leaf('删除工作表','home.deleteSheet')],
  format:[submenu('单元格大小',[leaf('行高…','home.rowHeight'),leaf('列宽…','home.columnWidth'),leaf('自动调整列宽','home.autofitColumnWidth')]),submenu('可见性',[leaf('隐藏行','home.hideRows'),leaf('隐藏列','home.hideColumns')]),leaf('设置单元格格式…','home.formatCells')],
  sum:[leaf('求和','formulas.autoSum'),leaf('平均值'),leaf('计数'),leaf('最大值'),leaf('最小值')],
  fill:[leaf('向下','edit.fillDown'),leaf('向右','edit.fillRight'),leaf('序列…','edit.fillSeries')],
  clear:[leaf('全部清除','edit.clearAll'),leaf('清除格式','edit.clearFormats'),leaf('清除内容','edit.clearContents')],
  sortFilter:[leaf('升序','data.sortAscending'),leaf('降序','data.sortDescending'),leaf('自定义排序…','data.sort'),leaf('筛选','data.filter')],
  find:[leaf('查找…','edit.find'),leaf('替换…','edit.replace'),leaf('定位…','selection.set')],
  pivot:[leaf('从表格/区域'),leaf('推荐的数据透视表')],table:[leaf('插入表格','insert.table')],
  pivotChart:['柱形图','条形图','折线图','饼图','圆环图','雷达图'].map(label=>leaf(label)),
  picture:[leaf('此设备…','insert.picture')],shape:[
    leaf('矩形','insert.shape',{kind:'rectangle'}),
    leaf('圆角矩形','insert.shape',{kind:'roundedRectangle'}),
    leaf('椭圆','insert.shape',{kind:'ellipse'}),
    leaf('三角形','insert.shape',{kind:'triangle'}),
    leaf('箭头','insert.shape',{kind:'arrow'}),
    leaf('文本框','insert.textBox'),
  ],
  chart:[submenu('柱形图',[leaf('簇状柱形图','insert.chart',{type:'column'}),leaf('堆积柱形图','insert.chart',{type:'column',subtype:'stacked'})]),submenu('折线图',[leaf('折线图','insert.chart',{type:'line'}),leaf('带数据标记折线图','insert.chart',{type:'line',subtype:'markers'})]),leaf('饼图','insert.chart',{type:'pie'})],
  sparkline:[leaf('折线'),leaf('柱形'),leaf('盈亏')],slicer:[leaf('插入切片器')],link:[leaf('插入链接…','insert.hyperlink')],symbol:[leaf('符号…')],
  themes:[leaf('默认主题')],themeColors:[leaf('默认颜色')],themeFonts:[leaf('默认字体')],
  margins:[leaf('普通'),leaf('窄'),leaf('宽'),leaf('自定义页边距…')],pageOrientation:[leaf('纵向'),leaf('横向')],paperSizes:[leaf('A4'),leaf('A3'),leaf('信纸')],
  printArea:[leaf('设置打印区域'),leaf('取消打印区域')],breaks:[leaf('插入分页符'),leaf('删除分页符'),leaf('重置所有分页符')],printTitles:[leaf('重复首行'),leaf('重复选定行'),leaf('清除打印标题')],fitPages:[leaf('自动'),leaf('1 页'),leaf('2 页'),leaf('3 页'),leaf('4 页'),leaf('5 页')],scale:[leaf('100%'),leaf('75%'),leaf('50%')],
  gridlines:[leaf('查看'),leaf('打印')],headings:[leaf('查看'),leaf('打印')],functions:[leaf('插入函数…')],functionCategories:[leaf('最近使用'),leaf('全部函数')],names:[leaf('选择名称…')],createNames:[leaf('顶端行'),leaf('最左列')],calcMode:[leaf('自动'),leaf('手动')],
  getData:[leaf('从文本/CSV…','data.fromTextCsv'),leaf('从工作簿…')],filter:[leaf('筛选','data.filter'),leaf('清除筛选','data.clearFilter')],validation:[leaf('数据验证…')],whatIf:[leaf('方案管理器'),leaf('单变量求解')],group:[leaf('组合'),leaf('自动创建分级显示')],ungroup:[leaf('取消组合')],
  translate:[leaf('翻译…')],comments:[leaf('显示所有批注')],notes:[leaf('新建注释'),leaf('显示/隐藏注释'),leaf('显示所有注释'),leaf('转换为注释'),leaf('注释图片窗格')],protect:[leaf('保护工作表…'),leaf('保护工作簿…')],
  zoom:[leaf('200%'),leaf('100%','view.zoom100'),leaf('75%'),leaf('选定区域')],freeze:[leaf('冻结窗格'),leaf('冻结首行'),leaf('冻结首列')],
  chartElements:[leaf('图表标题'),leaf('坐标轴'),leaf('数据标签')],chartLayouts:[leaf('布局 1'),leaf('布局 2')],align:[leaf('左对齐'),leaf('水平居中'),leaf('右对齐')],
  sheetTab:[
    leaf('插入工作表','home.insertSheet'),leaf('删除工作表','home.deleteSheet'),
    leaf('重命名','sheet.rename'),leaf('移动或复制…','sheet.move'),
    leaf('保护工作表…'),submenu('工作表标签颜色',[
      leaf('无颜色','sheet.tabColor',{color:'none'}),
      submenu('主题颜色',[
        leaf('白色','sheet.tabColor',{color:'#FFFFFF'}),leaf('黑色','sheet.tabColor',{color:'#000000'}),
        leaf('灰色','sheet.tabColor',{color:'#808080'}),leaf('蓝色','sheet.tabColor',{color:'#4472C4'}),
        leaf('橙色','sheet.tabColor',{color:'#ED7D31'}),leaf('黄色','sheet.tabColor',{color:'#FFC000'}),
        leaf('绿色','sheet.tabColor',{color:'#70AD47'}),leaf('紫色','sheet.tabColor',{color:'#7030A0'}),
      ]),
      submenu('标准颜色',[
        leaf('深红色','sheet.tabColor',{color:'#C00000'}),leaf('红色','sheet.tabColor',{color:'#FF0000'}),
        leaf('橙色','sheet.tabColor',{color:'#FF9900'}),leaf('黄色','sheet.tabColor',{color:'#FFFF00'}),
        leaf('绿色','sheet.tabColor',{color:'#00B050'}),leaf('青色','sheet.tabColor',{color:'#00B0F0'}),
        leaf('蓝色','sheet.tabColor',{color:'#0070C0'}),leaf('紫色','sheet.tabColor',{color:'#7030A0'}),
      ]),
      leaf('更多颜色…','sheet.tabColor',{color:'custom'}),
    ],'colorPalette'),leaf('隐藏','sheet.hide'),leaf('取消隐藏…','sheet.unhide'),leaf('选定全部工作表'),
  ],
}

const chrome = {
  profile:'openmuse-spreadsheet-chrome/1', initialTab:'home',
  metrics:{tabHeight:35,ribbonHeight:80,compactRibbonHeight:48,formulaHeight:40,sheetTabsHeight:42,statusHeight:24,aiRailWidth:34,
    ribbonLargeWidth:45,ribbonLargeWideWidth:58,ribbonFontNameWidth:130,ribbonFontSizeWidth:50,ribbonNumberFormatWidth:88,
    statusHorizontalPadding:12,statusZoomSliderWidth:110,statusViewButtonWidth:22,statusViewGap:2,
    rowHeaderWidth:46,columnHeaderHeight:20,dialogBackdropBlur:4,dialogBackdropOpacity:0.5},
  showRibbonGroupCaptions:false,
  colors:{chrome:'#202020',surface:'#242424',canvas:'#191919',grid:'#232323',text:'#e8e8e8',muted:'#aaaaaa',border:'#414141',accent:'#34a853',
    statusBackground:'#252525',statusBorder:'#3a3a3a',statusZoom:'#777777',statusSelectedBackground:'#1d3328',
    dialogPrimary:'#e4e4e4',dialogPrimaryText:'#1e1e1e',dialogFocus:'#8ab4f8',dialogBackdrop:'#000000'},
  statusMessages:{ready:'工作簿已加载，行列可编辑。',modified:'工作簿已修改',
    limitedObjects:'对象预览受限',limitedRows:'行尺寸预览受限'},
  statusViews:[
    {value:'normal',label:'普通视图',icon:'grid_view',command:'view.normal'},
    {value:'pageBreakPreview',label:'分页预览',icon:'view_array',command:'view.pageBreakPreview'},
  ],
  zoomDialog:{title:'缩放',magnification:'缩放比例',fitSelection:'恰好容纳选定区域',custom:'自定义',
    cancel:'取消',confirm:'确定',rangeError:'请输入 10 到 400 之间的数字。',
    presets:[200,100,75,50,25],min:10,max:400,
    zoomCommand:'view.zoom',fitSelectionCommand:'view.zoomToSelection'},
  goToDialog:{title:'定位（Go To）',reference:'引用位置',placeholder:'例如 A1 或 B2:D20',
    hint:'输入单元格或矩形区域引用。',invalidReference:'请输入有效的单元格或区域引用。',
    cancel:'取消',confirm:'定位',command:'selection.set'},
  statusStatistics:[
    {id:'AVERAGE',label:'平均值',defaultEnabled:true},
    {id:'COUNTA',label:'计数',defaultEnabled:true},
    {id:'COUNT',label:'数值计数',defaultEnabled:false},
    {id:'MIN',label:'最小值',defaultEnabled:false},
    {id:'MAX',label:'最大值',defaultEnabled:false},
    {id:'SUM',label:'求和',defaultEnabled:true},
  ],
  sheetTabColorPalette,
  sheetTabMenu:'sheetTab',
  visualActions:{move:'object.move',resize:'object.move',delete:'object.delete'},
  quickAccess:[
    {id:'save',label:'保存',icon:'save',command:'file.saveBytes'},
    {id:'saveAs',label:'另存为',icon:'save_as',command:'file.saveAs'},
    {id:'undo',label:'撤销',icon:'undo',command:'edit.undo'},
    {id:'redo',label:'重做',icon:'redo',command:'edit.redo'},
    {id:'autoSave',label:'自动保存',icon:'toggle_off',command:'file.autoSave'},
  ],
  tabs, menus,
}

const mapped = new Set(['file.saveBytes','edit.undo','edit.redo','selection.set','cell.set','sheet.activate','sheet.insert','view.zoom','view.zoom100'])
for (const command of Object.values(chrome.visualActions)) mapped.add(command)
for (const view of chrome.statusViews) mapped.add(view.command)
mapped.add(chrome.zoomDialog.zoomCommand)
mapped.add(chrome.zoomDialog.fitSelectionCommand)
for (const item of chrome.quickAccess) if (item.command) mapped.add(item.command)
for (const t of tabs) for (const g of t.groups) for (const item of g.items) if (item.command) mapped.add(item.command)
for (const items of Object.values(menus)) {
  const visit = list => {for (const item of list) {if(item.command)mapped.add(item.command);if(item.children)visit(item.children)}}
  visit(items)
}
const commands = {
  profile:'openmuse-spreadsheet-commands/1',
  commands:[...mapped].sort().map(id=>({id,target:id.startsWith('file.')?'host':id.startsWith('view.')?'view':'engine',feature:id.startsWith('file.')?'spreadsheet.file':id.startsWith('view.')?'spreadsheet.view':'spreadsheet.edit'})),
}
const features = {profile:'openmuse-spreadsheet-features/1',features:[
  {id:'spreadsheet.file',defaultEnabled:true},
  {id:'spreadsheet.view',defaultEnabled:true},
  {id:'spreadsheet.edit',defaultEnabled:true},
  {id:'spreadsheet.ai',defaultEnabled:false},
]}
await Promise.all([out('chrome.json',chrome),out('commands.json',commands),out('features.json',features)])
console.log(JSON.stringify({tabs:tabs.length,groups:tabs.reduce((n,t)=>n+t.groups.length,0),controls:tabs.reduce((n,t)=>n+t.groups.reduce((m,g)=>m+g.items.length,0),0),menus:Object.keys(menus).length}))
