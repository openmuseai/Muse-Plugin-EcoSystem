# GenOffice Ribbon 菜单逐项台账

参考源码为 `plugins/genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/components`。台账枚举源码里的 `dropdown` 键；每个键对应一个已签名产品菜单树，并由 Flutter 的递归菜单组件呈现。当前状态是**层级与入口已建立**；动态字体/颜色/样式/表格网格、图标、状态勾选和真实编辑命令仍需逐项验收。

| 源码文件 | `dropdown` 键 | 产品菜单 ID | 当前层级 |
| --- | --- | --- | --- |
| `Ribbon.tsx` | `fontFamily` | `home.fontFamily` | 1 级 |
| `Ribbon.tsx` | `file` | `file` | 1 级平铺 |
| `Ribbon.tsx` | `shapeFill` | `context.shapeFill` | 1 级 |
| `Ribbon.tsx` | `shapeOutline` | `context.shapeOutline` | 1 级 |
| `Ribbon.tsx` | `shapeTextColor` | `context.shapeTextColor` | 1 级 |
| `Ribbon.tsx` | `tableShading` | `context.tableShading` | 1 级 |
| `Ribbon.tsx` | `tableBorders` | `context.tableBorders` | 1 级 |
| `Ribbon.tsx` | `tableBorderColor` | `context.tableBorderColor` | 1 级 |
| `Ribbon.tsx` | `tableSelect` | `context.tableSelect` | 1 级 |
| `Ribbon.tsx` | `tableDelete` | `context.tableDelete` | 1 级 |
| `Ribbon.tsx` | `tableAutoFit` | `context.tableAutoFit` | 1 级 |
| `Ribbon.tsx` | `cellTextDirection` | `context.cellTextDirection` | 1 级 |
| `Ribbon.tsx` | `convert` | `home.convert` | 1 级 |
| `Ribbon.tsx` | `paste` | `home.paste` | 1 级 |
| `Ribbon.tsx` | `fontSize` | `home.fontSize` | 1 级 |
| `Ribbon.tsx` | `case` | `home.case` | 1 级 |
| `Ribbon.tsx` | `highlight` | `home.highlight` | 1 级 |
| `Ribbon.tsx` | `color` | `home.fontColor` | 1 级 |
| `Ribbon.tsx` | `bulletLib` | `home.bullets` | 1 级；图库格子为同一弹层内的叶节点 |
| `Ribbon.tsx` | `numberLib` | `home.numbering` | 1 级；图库格子为同一弹层内的叶节点 |
| `Ribbon.tsx` | `multiLib` | `home.multilevel` | 1 级；图库格子为同一弹层内的叶节点 |
| `Ribbon.tsx` | `spacing` | `home.spacing` | 1 级 |
| `Ribbon.tsx` | `shading` | `home.shading` | 1 级 |
| `Ribbon.tsx` | `borders` | `home.borders` | 1 级 |
| `Ribbon.tsx` | `styleGallery` | `home.styles` | 1 级 |
| `ribbon-design-tab.tsx` | `theme` | `design.theme` | 1 级 |
| `ribbon-design-tab.tsx` | `themefonts` | `design.fonts` | 1 级 |
| `ribbon-design-tab.tsx` | `themecolors` | `design.colors` | 1 级 |
| `ribbon-design-tab.tsx` | `pagecolor` | `design.pageColor` | 1 级 |
| `ribbon-design-tab.tsx` | `watermark` | `design.watermark` | 1 级 |
| `ribbon-design-tab.tsx` | `pgborders` | `design.pageBorders` | 1 级 |
| `ribbon-hf-tab.tsx` | `hf-header` | `context.hfHeader` | 1 级 |
| `ribbon-hf-tab.tsx` | `hf-footer` | `context.hfFooter` | 1 级 |
| `ribbon-hf-tab.tsx` | `hf-pagenum` | `context.hfPageNumber` | 1 级平铺 |
| `ribbon-hf-tab.tsx` | `hf-datetime` | `context.hfDateTime` | 1 级 |
| `ribbon-insert-tab.tsx` | `cover` | `insert.cover` | 1 级 |
| `ribbon-insert-tab.tsx` | `table` | `insert.table` | 2 级 |
| `ribbon-insert-tab.tsx` | `shape` | `insert.shapes` | 2 级 |
| `ribbon-insert-tab.tsx` | `textBox` | `insert.textBox` | 1 级 |
| `ribbon-insert-tab.tsx` | `wordArt` | `insert.wordArt` | 1 级 |
| `ribbon-insert-tab.tsx` | `dropCap` | `insert.dropCap` | 1 级 |
| `ribbon-insert-tab.tsx` | `field` | `insert.field` | 1 级 |
| `ribbon-insert-tab.tsx` | `header` | `insert.header` | 1 级 |
| `ribbon-insert-tab.tsx` | `footer` | `insert.footer` | 1 级 |
| `ribbon-insert-tab.tsx` | `pagenum` | `insert.pageNumber` | 1 级平铺 |
| `ribbon-insert-tab.tsx` | `symbol` | `insert.symbol` | 1 级 |
| `ribbon-insert-tab.tsx` | `equation` | `insert.equation` | 1 级 |
| `ribbon-layout-tab.tsx` | `margins` | `layout.margins` | 1 级 |
| `ribbon-layout-tab.tsx` | `orient` | `layout.orientation` | 1 级 |
| `ribbon-layout-tab.tsx` | `paper` | `layout.paper` | 1 级 |
| `ribbon-layout-tab.tsx` | `columns` | `layout.columns` | 1 级 |
| `ribbon-layout-tab.tsx` | `sectbreak` | `layout.breaks` | 1 级 |
| `ribbon-layout-tab.tsx` | `arrange-pos` | `layout.position` | 2 级：嵌入型与 3×3 位置网格 |
| `ribbon-layout-tab.tsx` | `arrange-wrap` | `layout.wrap` | 1 级 |
| `ribbon-references-tab.tsx` | `zotero-settings` | `references.zoteroSettings` | 1 级 |
| `ribbon-references-tab.tsx` | `citation` | `references.citation` | 1 级 |
| `ribbon-references-tab.tsx` | `index` | `references.index` | 1 级 |
| `ribbon-tabs.tsx` | `translate` | `review.translate` | 1 级 |
| `ribbon-tabs.tsx` | `deleteComment` | `review.deleteComment` | 1 级 |
| `ribbon-tabs.tsx` | `revDisplay` | `review.revisionDisplay` | 1 级 |
| `ribbon-tabs.tsx` | `acceptRev` | `review.accept` | 1 级 |
| `ribbon-tabs.tsx` | `rejectRev` | `review.reject` | 1 级 |

源码下拉键共 **62** 个；插件菜单树共 **63** 棵。额外的 `context.pictureRotate` 是图片旋转菜单。`layout.position` 在 0.1.5 中修正为源码的九宫格；0.1.6 又将文件转换、两处页码菜单改为源码的平铺项，并将三种列表菜单改为图库加级别行。0.1.7 将首字下沉改为三列图形选项，并依 `EquationModal.tsx` 补齐 **8** 个内置公式及单列预览，保留“插入新公式”独立入口。此前人为添加的子菜单层级与源码不符。插入图库现与源码数据数量对齐：符号 **50**、封面 **12**、艺术字 **12**、形状 **7 组 109 项**、公式 **8**。形状源码注释称 104，但数组实际包含 109 项；审计脚本比对数组。形状预览路径存入签名 `menus.json`，`npm run audit:shape-previews` 验证与当前 GenOffice 几何一致，`npm run sync:shape-previews` 用于源码升级后重生路径。公式预览现为可离线显示的 Unicode 摘要，尚待原生数学排版缩略图与源 MathML 逐式比对。

## 递归菜单合同

- `ProductPackage` 中的 `menus.json` 与 `ribbon.json` 一起签名；Ribbon 控件只能引用同包菜单 ID。节点为 `heading`、`separator`、`submenu`、`grid` 或 `action`，子菜单最多 4 级，整个包最多 2000 个节点。`grid.presentation` 明确区分主题/标准色板、高亮色、表格选取器、样式图库、封面图库、艺术字、符号库、形状库、首字下沉及单列公式库；验证器拒绝未知类型或错误网格尺寸，`previewText` 仅允许有界的显示数据。
- 桌面 Flutter `MenuAnchor` 锚定控件；`SubmenuButton` 打开下一层，Esc/外部点击关闭。触控平台与窄屏使用同一菜单树的底部面板，逐层进入/返回，避免第三级及第四级菜单离开视口；网格格子 44px，超出宽度横向滚动。只有带有已协商命令 ID 的叶节点可执行，插件不参与逐字输入。
- 主题色 10×6、标准色 10 格、高亮色 5×3 与表格 10×8 的静态布局和色值已按 GenOffice 源码编码。动态菜单（字体库、最近使用列表、当前颜色/样式、引文源）下一阶段改为 `provider` 槽位，由 Host/word-core 的只读快照填充，插件仅定义呈现规则和命令 ID。静态样本不冒充真实文档状态。

## 响应式验收矩阵

| 视口宽度 | 形态 | Ribbon 高度 | 交互要求 |
| --- | --- | ---: | --- |
| ≥1100，鼠标桌面 | 完整双行 Ribbon | 80 | 与 1365×860 GenOffice 参照逐区比对 |
| 700–1099 或触控大屏 | 平板 | 64 | 图标加短标签，水平访问全部控件 |
| 480–699 | 折叠屏/窄平板 | 52 | 紧凑图标，菜单锚点不越界 |
| <480 | 手机 | 45 | 控件触达高度至少 44px、横向滚动、状态栏 44px；长菜单受视口高度约束并滚动 |

下一验收批次：对 63 棵菜单逐个录制截图与键盘/触控轨迹，动态提供器和命令可用性逐项接入；完成前不得将菜单外观标记为 1:1 完成。桌面端到端测试覆盖形状图库、平铺页码位置、列表图库及位置九宫格；触屏测试覆盖弹层内图库和可返回的递归菜单能力。
