# Spreadsheet 壳第二轮：Ribbon 混排与多端证据（2026-10-23）

## 本轮改动与架构边界

对照 `vendor/genoffice/apps/sheets/src/renderer/ExcelShell.tsx` 的 `HomeRibbon` 与 `styles.css` 的 `.ribbon-group`、`.ribbon-rows`、`.tool-stack`、`.ribbon-tool.large` 后，将「开始」页 8 组从等尺寸按钮改为大按钮、三项竖列和两排紧凑控件混排。组内的布局顺序存入已签名的 `product/chrome.json`；通用 Flutter `spreadsheet_editor` 只实现 `large`、`stack`、`rows` 三个呈现原语。校验器要求布局恰好覆盖组内所有控件且无重复。补齐当前 120 个 Ribbon 图标的 Flutter 映射，移除方格占位。产品包升至 `0.1.1`，引擎 ABI 与表面主版本仍为 1。

文档、单元格编辑和导出仍由 Host 随包的 GridCraft Rust 适配层持有；市场功能包仅控制入口、分组、菜单树和资源。菜单节点继续按资源递归构造，未接内核的命令保留禁用说明。

## 视觉对比

| 样本 | 证据 | 观察 |
| --- | --- | --- |
| GenOffice 参考，2750×1706 | [参考截图](evidence/round-2/genoffice-reference.png) | 深色顶部七标签；开始页大 AI/剪贴板、双排字体/对齐/数字、三项样式/单元格；下方公式栏、网格、表签和状态栏。 |
| 第一轮，1365×860 | [第一轮开始页](evidence/round-1/desktop-home.png) | 所有工具被画为单排等尺寸按钮，字体/数字缺少输入框形状。 |
| 第二轮，1365×860 | [第二轮开始页](evidence/round-2/desktop-home.png) | 同序八组；AI/粘贴使用大按钮，剪贴板与样式/单元格为竖列，字体/对齐/数字为双排；Aptos/11/常规呈现为字段，所有资源图标有对应 glyph。顶部仍可横向滚动。 |
| 多级菜单 | [边框菜单](evidence/round-2/desktop-border-submenu.png) | 签名资源的一级和二级节点在 Host 浮层中可点击；更深层级使用相同递归组件。 |
| 其他常驻标签 | [插入](evidence/round-2/desktop-insert.png) · [页面布局](evidence/round-2/desktop-pageLayout.png) · [公式](evidence/round-2/desktop-formulas.png) · [数据](evidence/round-2/desktop-data.png) · [审阅](evidence/round-2/desktop-review.png) · [视图](evidence/round-2/desktop-view.png) | 七个常驻标签均从插件资源构建，组和菜单入口可见。其他标签尚未做 GenOffice 的逐控件排布。 |
| 响应式 | [平板 834×1112](evidence/round-2/tablet-view.png) · [折叠宽度 720×900](evidence/round-2/foldable-view.png) · [手机 390×844](evidence/round-2/mobile-view.png) | 共用 Flutter 表面在窄宽度压缩为可横向滚动的图标 Ribbon；公式栏、网格、表签和缩放控件继续可见。此项是组件级截图，非本轮真实手机启动截图。 |

参考图与本轮测试工作簿不是同一份文档，且物理像素尺寸不同；因此只比较壳层级、顺序和控件形状，不宣称像素级一致。第二轮的桌面截图也显示部分禁用控件偏灰、字体字段为静态回显、右端编辑组横向溢出，这些仍需校准。

## 构建与端到端结果

- [构建报告](evidence/round-2/build-report.json)记录 `0.1.1` 产品包、Rust 库、macOS ZIP、Android APK、样本工作簿与源码的 SHA-256；包内产品文件与独立签名包哈希一致。
- `npm run generate && npm run validate && npm run pack && npm run verify` 通过；签名包加载与篡改拒绝测试通过。资源为 11 个标签、55 组、157 个控件、62 棵菜单树。
- `flutter test test/spreadsheet_product_e2e_test.dart` 通过：Host 路由打开真实 XLSX，读取 Region/North 和公式结果 267，改 B2 为 126，导出并重开，验证边框嵌套菜单，并生成桌面、平板、折叠和小屏截图。
- macOS Release `OpenMuse.app` 和 ZIP 构建完成；`codesign --verify --deep --strict` 通过；DSH closure 的无密钥检查通过。
- Android arm64 Release APK 构建完成，含 `libopenmuse_gridcraft_bridge.so` 和 `spreadsheet.mcpb`；`apksigner verify` 的 v2/v3 签名检查通过。此轮没有对当前连接的实体手机执行安装/打开，所以端上结果沿用第一轮模拟器证据，APK 供人工验证。

一键复现：在工作区运行 `bash Muse-Client/scripts/spreadsheet-product-e2e.sh all`。后续每次运行使用带时间戳的独立证据目录，避免旧截图混入新报告。当前包使用本地开发签名密钥和 Android 本地调试签名，不是市场发行证书。

## 仍未达到一比一的范围

1. GenOffice 使用 Univer 的虚拟网格和对象层；当前 Flutter 网格仍是前 100 行×32 列快照，未支持大型文档可视范围加载、图表/图片对象、冻结、列宽行高及完整原位 IME。
2. 四个上下文标签已在签名资源中登记，尚未按图表、表格、形状、图片选区自动出现。其余六个常驻标签仍需逐项混排、下拉状态与弹窗视觉核对。
3. 字体和数字字段暂为静态默认值；菜单节点和按钮仍有未接 GridCraft 的命令。粘贴等带主命令的菜单按钮还需拆成主点击与菜单箭头。底部缺少聚合统计和可切换视图状态，缩放百分比未驱动网格几何。
4. 手机/折叠屏已验证无裁剪的组件布局，但触控密度、横屏、系统字体放大与实体设备文件工作流需要继续验收。

下一轮优先做可视区域网格与引擎分块快照、命令的 split-button 语义和状态回显，再按同一份语料输出 GenOffice 与 OpenMuse 的同尺寸实机截图。
